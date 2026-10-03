//
//  BlobUploader.swift
//  FlipcashCore
//

import Foundation

private let logger = Logger(label: "flipcash.blob-uploader")

/// The blob RPCs an upload depends on.
protocol BlobReserving: Sendable {
    /// Reserves an upload of `sizeBytes`, end-to-end encrypted for the DM `encryptedFor` when set.
    func initiateExternalUpload(mimeType: String, sizeBytes: Int, encryptedFor: ConversationID?, owner: KeyPair) async throws -> ReservedUpload
    func completeExternalUpload(blobID: BlobID, owner: KeyPair) async throws -> BlobState
    func blobState(blobID: BlobID, owner: KeyPair) async throws -> BlobState
}

/// Stores bytes in blob storage and waits for the server to finalize them.
///
/// Stateless — every call carries its own bytes, so instances are shareable.
final class BlobUploader: Sendable {

    private let reserving: BlobReserving
    private let transport: BlobUploading
    private let pollInterval: Duration
    private let timeout: Duration

    init(
        reserving: BlobReserving,
        transport: BlobUploading,
        pollInterval: Duration = .seconds(2),
        timeout: Duration = .seconds(60)
    ) {
        self.reserving    = reserving
        self.transport    = transport
        self.pollInterval = pollInterval
        self.timeout      = timeout
    }

    /// Stores `data` and returns its blob, leaving finalization to the caller.
    ///
    /// Separate from `awaitFinalization` so a caller whose poll times out can
    /// resume the same blob instead of uploading a second copy.
    ///
    /// `onProgress` hears the bytes going out to storage, from any thread.
    func store(
        _ data: Data,
        mimeType: String,
        owner: KeyPair,
        onProgress: @escaping @Sendable (BlobUploadProgress) -> Void = { _ in }
    ) async throws -> BlobID {
        // Sanitize before reserving: the reservation signs the byte count, and
        // storage refuses an image carrying personal metadata. Doing it here
        // rather than at the call site is what makes it true of every upload.
        let data = JPEGMetadata.stripped(data)

        let reserved = try await reserving.initiateExternalUpload(
            mimeType: mimeType,
            sizeBytes: data.count,
            encryptedFor: nil,
            owner: owner
        )

        logger.info("Reserved blob upload", metadata: [
            "blobId": "\(reserved.blobID)",
            "mimeType": "\(mimeType)",
            "sizeBytes": "\(data.count)",
        ])

        try await store(data, mimeType: mimeType, to: reserved.target, onProgress: onProgress)

        switch try await reserving.completeExternalUpload(blobID: reserved.blobID, owner: owner) {
        case .rejected(let reason):
            logger.info("Blob rejected on completion", metadata: [
                "blobId": "\(reserved.blobID)",
                "reason": "\(reason)",
            ])
            throw ErrorBlob.rejected(reason)
        case .ready, .pending, .processing:
            return reserved.blobID
        }
    }

    /// Stores `image` encrypted for the DM `conversationID` and returns its blob, leaving
    /// finalization to the caller.
    ///
    /// `encrypt` seals the plaintext under the blob id the reservation assigns, which is part of
    /// its aad, so the reservation declares the sealed size before the blob exists. `onProgress`
    /// hears the sealed bytes going out to storage, from any thread.
    func storeEncrypted(
        _ image: Data,
        for conversationID: ConversationID,
        owner: KeyPair,
        onProgress: @escaping @Sendable (BlobUploadProgress) -> Void = { _ in },
        encrypt: @Sendable (Data, BlobID) throws -> Data
    ) async throws -> EncryptedBlobUpload {
        // The server never reads these bytes, so stripping location and camera metadata is on us.
        let plaintext = JPEGMetadata.stripped(image)
        let sizeBytes = plaintext.count + EncryptedBlobUpload.overhead

        let reserved = try await reserving.initiateExternalUpload(
            mimeType: Self.encryptedMimeType,
            sizeBytes: sizeBytes,
            encryptedFor: conversationID,
            owner: owner
        )

        logger.info("Reserved encrypted blob upload", metadata: [
            "blobId": "\(reserved.blobID)",
            "sizeBytes": "\(sizeBytes)",
        ])

        let blob = try encrypt(plaintext, reserved.blobID)
        guard blob.count == sizeBytes else {
            logger.error("Encrypted blob is not the size reserved", metadata: [
                "blobId": "\(reserved.blobID)",
                "reserved": "\(sizeBytes)",
                "actual": "\(blob.count)",
            ])
            throw ErrorBlob.unknown
        }

        try await store(blob, mimeType: Self.encryptedMimeType, to: reserved.target, onProgress: onProgress)

        switch try await reserving.completeExternalUpload(blobID: reserved.blobID, owner: owner) {
        case .rejected(let reason):
            logger.info("Blob rejected on completion", metadata: [
                "blobId": "\(reserved.blobID)",
                "reason": "\(reason)",
            ])
            throw ErrorBlob.rejected(reason)
        case .ready, .pending, .processing:
            return EncryptedBlobUpload(blobID: reserved.blobID, plaintextSize: plaintext.count)
        }
    }

    /// The MIME type every end-to-end encrypted upload declares; the server refuses any other.
    static let encryptedMimeType = "application/octet-stream"

    /// Polls until the blob is finalized.
    ///
    /// Returns immediately when it is already ready; a rejection is terminal. A poll lost in transit
    /// is retried, since iOS drops the connection when it suspends the app mid-wait. The `timeout`
    /// budget is counted in polls rather than wall time, so time spent suspended doesn't use it up.
    func awaitFinalization(blobID: BlobID, owner: KeyPair) async throws {
        let maxPolls = max(1, Int((timeout / pollInterval).rounded(.up)))
        var polls = 0

        while true {
            try Task.checkCancellation()
            polls += 1

            do {
                switch try await reserving.blobState(blobID: blobID, owner: owner) {
                case .ready:
                    return
                case .rejected(let reason):
                    logger.info("Blob rejected", metadata: [
                        "blobId": "\(blobID)",
                        "reason": "\(reason)",
                    ])
                    throw ErrorBlob.rejected(reason)
                case .pending, .processing:
                    break
                }
            } catch ErrorBlob.network(let error) {
                try Task.checkCancellation()
                logger.info("Blob poll lost in transit", metadata: [
                    "blobId": "\(blobID)",
                    "error": "\(error)",
                ])
            }

            guard polls < maxPolls else {
                logger.info("Blob finalization timed out", metadata: ["blobId": "\(blobID)"])
                throw ErrorBlob.timedOut
            }

            try await Task.sleep(for: pollInterval)
        }
    }

    // MARK: - Upload -

    private func store(
        _ data: Data,
        mimeType: String,
        to target: UploadTarget,
        onProgress: @escaping @Sendable (BlobUploadProgress) -> Void
    ) async throws {
        let boundary = "Boundary-\(UUID().uuidString)"

        let status: Int
        let responseBody: Data

        do {
            // The upload leg is plain HTTP, so its failures arrive as `URLError`
            // rather than an `ErrorBlob`; wrapping keeps network weather out of
            // the caller's generic catch, which reports as a defect.
            (status, responseBody) = try await transport.post(
                url: target.url,
                contentType: "multipart/form-data; boundary=\(boundary)",
                headers: target.headers,
                body: Self.multipartBody(
                    fields: target.formFields,
                    file: data,
                    mimeType: mimeType,
                    boundary: boundary
                ),
                onProgress: onProgress
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            logger.info("Upload transport failed", metadata: ["error": "\(error)"])
            throw ErrorBlob.network(error)
        }

        guard (200..<300).contains(status) else {
            // Storage reports signature and policy failures only in the body.
            logger.error("Storage refused the upload", metadata: [
                "status": "\(status)",
                "response": "\(String(decoding: responseBody.prefix(1024), as: UTF8.self))",
            ])
            throw ErrorBlob.uploadFailed(status)
        }
    }

    /// Builds the `multipart/form-data` body: the signed policy fields in a
    /// stable order, then the file.
    ///
    /// Storage ignores every field after the file part, so it must come last.
    static func multipartBody(fields: [String: String], file: Data, mimeType: String, boundary: String) -> Data {
        var body = Data()

        for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.append("\(value)\r\n")
        }

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"blob\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(file)
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")

        return body
    }
}

/// An encrypted blob stored but not yet finalized, with the length of the plaintext it seals.
public struct EncryptedBlobUpload: Hashable, Sendable {
    /// The blob the reservation assigned.
    public let blobID: BlobID
    /// The plaintext image's length after metadata stripping, the length the recipient checks.
    public let plaintextSize: Int

    /// What encryption adds to an image: the 24-byte nonce ahead of the ciphertext and the 16-byte
    /// tag after it.
    public static let overhead = 40
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
