//
//  BlobUploader.swift
//  FlipcashCore
//

import Foundation

private let logger = Logger(label: "flipcash.blob-uploader")

/// The blob RPCs an upload depends on.
protocol BlobReserving: Sendable {
    func initiateExternalUpload(mimeType: String, sizeBytes: Int, owner: KeyPair) async throws -> ReservedUpload
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

    /// Uploads `data` and returns its blob once the server has finalized it.
    func upload(_ data: Data, mimeType: String, owner: KeyPair) async throws -> BlobID {
        let reserved = try await reserving.initiateExternalUpload(
            mimeType: mimeType,
            sizeBytes: data.count,
            owner: owner
        )

        logger.info("Reserved blob upload", metadata: [
            "blobId": "\(reserved.blobID)",
            "mimeType": "\(mimeType)",
            "sizeBytes": "\(data.count)",
        ])

        try await store(data, mimeType: mimeType, to: reserved.target)

        switch try await reserving.completeExternalUpload(blobID: reserved.blobID, owner: owner) {
        case .ready:
            return reserved.blobID
        case .rejected(let reason):
            throw ErrorBlob.rejected(reason)
        case .pending, .processing:
            try await awaitFinalization(blobID: reserved.blobID, owner: owner)
            return reserved.blobID
        }
    }

    /// Polls until the blob is finalized.
    ///
    /// Separate from `upload(_:mimeType:owner:)` so a timed-out attempt can be
    /// resumed: the bytes are already stored, and a rejection is terminal.
    func awaitFinalization(blobID: BlobID, owner: KeyPair) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)

        while true {
            try Task.checkCancellation()

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

            guard ContinuousClock.now < deadline else {
                logger.info("Blob finalization timed out", metadata: ["blobId": "\(blobID)"])
                throw ErrorBlob.timedOut
            }

            try await Task.sleep(for: pollInterval)
        }
    }

    // MARK: - Upload -

    private func store(_ data: Data, mimeType: String, to target: UploadTarget) async throws {
        let boundary = "Boundary-\(UUID().uuidString)"

        let (status, responseBody) = try await transport.post(
            url: target.url,
            contentType: "multipart/form-data; boundary=\(boundary)",
            headers: target.headers,
            body: Self.multipartBody(
                fields: target.formFields,
                file: data,
                mimeType: mimeType,
                boundary: boundary
            )
        )

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

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
