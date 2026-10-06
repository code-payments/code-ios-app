//
//  BlobUploaderTests.swift
//  FlipcashCoreTests
//

import Foundation
import Synchronization
import Testing
@testable import FlipcashCore

@Suite("Blob upload")
struct BlobUploaderTests {

    // MARK: - End-to-end encrypted -

    @Test("An encrypted upload reserves for its DM, as an opaque blob the size of the sealed bytes")
    func encryptedUploadReservesForChat() async throws {
        let transport = RecordingTransport()
        let reserving = StubReserving(states: [.ready])
        let uploader = BlobUploader(reserving: reserving, transport: transport, pollInterval: .milliseconds(1), timeout: .seconds(5))
        let conversationID = ConversationID(data: Data(repeating: 7, count: 32))
        let sealed = Data(repeating: 0xCD, count: Self.fileBytes.count + EncryptedBlobUpload.overhead)

        let upload = try await uploader.storeEncrypted(Self.fileBytes, for: conversationID, owner: try Self.owner()) { plaintext, blobID in
            #expect(blobID == StubReserving.blobID)
            #expect(plaintext == Self.fileBytes)
            return sealed
        }

        #expect(upload == EncryptedBlobUpload(blobID: StubReserving.blobID, plaintextSize: Self.fileBytes.count))
        #expect(await reserving.encryptedFor == conversationID)
        #expect(await reserving.declaredMimeType == "application/octet-stream")
        #expect(await reserving.declaredSizeBytes == sealed.count)
        let parsed = try await Self.parse(transport)
        #expect(parsed.file == sealed)
    }

    @Test("Metadata is stripped before encrypting, and the plaintext size is the stripped length")
    func encryptedUploadStripsBeforeSealing() async throws {
        let uploader = makeUploader(transport: RecordingTransport(), states: [.ready])
        let jpeg = Self.jpegCarryingComment()
        let stripped = JPEGMetadata.stripped(jpeg)
        #expect(stripped.count < jpeg.count)

        let upload = try await uploader.storeEncrypted(jpeg, for: ConversationID(data: Data(repeating: 7, count: 32)), owner: try Self.owner()) { plaintext, _ in
            #expect(plaintext == stripped)
            return Data(count: plaintext.count + EncryptedBlobUpload.overhead)
        }

        #expect(upload.plaintextSize == stripped.count)
    }

    @Test("A sealed blob of a size other than the one reserved is never uploaded")
    func encryptedUploadRefusesWrongSize() async throws {
        let transport = RecordingTransport()
        let uploader = makeUploader(transport: transport, states: [.ready])

        await #expect(throws: ErrorBlob.self) {
            _ = try await uploader.storeEncrypted(Self.fileBytes, for: ConversationID(data: Data(repeating: 7, count: 32)), owner: try Self.owner()) { plaintext, _ in
                plaintext
            }
        }
        #expect(await transport.body == nil)
    }

    // MARK: - Progress -

    @Test("Forwards the transport's sent-byte counts for a plaintext upload")
    func store_forwardsProgress() async throws {
        let uploader = makeUploader(transport: RecordingTransport(), states: [.ready])
        let seen = Mutex<[BlobUploadProgress]>([])

        _ = try await uploader.store(Self.fileBytes, mimeType: "image/jpeg", owner: try Self.owner()) { progress in
            seen.withLock { $0.append(progress) }
        }

        let fractions = seen.withLock { $0 }.compactMap(\.fraction)
        #expect(fractions.count == 2)
        #expect(fractions.first.map { $0 > 0 && $0 < 1 } == true)
        #expect(fractions.last == 1.0)
    }

    @Test("Forwards the sealed bytes' progress for an encrypted upload")
    func storeEncrypted_forwardsProgress() async throws {
        let uploader = makeUploader(transport: RecordingTransport(), states: [.ready])
        let seen = Mutex<[BlobUploadProgress]>([])

        _ = try await uploader.storeEncrypted(
            Self.fileBytes,
            for: ConversationID(data: Data(repeating: 7, count: 32)),
            owner: try Self.owner(),
            onProgress: { progress in seen.withLock { $0.append(progress) } }
        ) { plaintext, _ in
            Data(count: plaintext.count + EncryptedBlobUpload.overhead)
        }

        #expect(seen.withLock { $0 }.last?.fraction == 1.0)
    }

    @Test("Maps sent bytes to a fraction of the body, clamped to 0...1")
    func progress_fraction() {
        #expect(BlobUploadProgress(sentBytes: 0, totalBytes: 200).fraction == 0)
        #expect(BlobUploadProgress(sentBytes: 50, totalBytes: 200).fraction == 0.25)
        #expect(BlobUploadProgress(sentBytes: 200, totalBytes: 200).fraction == 1)
        #expect(BlobUploadProgress(sentBytes: 300, totalBytes: 200).fraction == 1)
        #expect(BlobUploadProgress(sentBytes: -1, totalBytes: 200).fraction == 0)
    }

    @Test("Reports no fraction when the body's length is unknown")
    func progress_unknownLength() {
        #expect(BlobUploadProgress(sentBytes: 10, totalBytes: 0).fraction == nil)
        #expect(BlobUploadProgress(sentBytes: 10, totalBytes: -1).fraction == nil)
    }

    @Test("The reservation names the chat only for an encrypted upload")
    func reservationRequestNamesChat() throws {
        let owner = try Self.owner()
        let conversationID = ConversationID(data: Data(repeating: 7, count: 32))

        let encrypted = BlobService.initiateRequest(mimeType: "application/octet-stream", sizeBytes: 10, encryptedFor: conversationID, owner: owner)
        let plain = BlobService.initiateRequest(mimeType: "image/jpeg", sizeBytes: 10, encryptedFor: nil, owner: owner)

        #expect(encrypted.endToEndEncryptedFor == .chat(conversationID.proto))
        #expect(plain.endToEndEncryptedFor == nil)
    }

    // MARK: - Multipart body -

    @Test("Signed policy fields come first, the file last")
    func multipartOrdersFileLast() async throws {
        let transport = RecordingTransport()
        let uploader = makeUploader(transport: transport, states: [.ready])

        _ = try await uploader.storeThenFinalize(Self.fileBytes, owner: try Self.owner())

        let parsed = try await Self.parse(transport)
        #expect(parsed.names.last == "file")
        #expect(Array(parsed.names.dropLast()) == ["Content-Type", "key", "policy", "x-amz-signature"])
    }

    @Test("Signed policy fields reach storage verbatim")
    func multipartPreservesSignedFields() async throws {
        let transport = RecordingTransport()
        let uploader = makeUploader(transport: transport, states: [.ready])

        _ = try await uploader.storeThenFinalize(Self.fileBytes, owner: try Self.owner())

        let parsed = try await Self.parse(transport)
        for (name, value) in Self.formFields {
            #expect(parsed.values[name] == value)
        }
    }

    @Test("The boundary declared in Content-Type is the one delimiting the body")
    func multipartBoundaryMatchesContentType() async throws {
        let transport = RecordingTransport()
        let uploader = makeUploader(transport: transport, states: [.ready])

        _ = try await uploader.storeThenFinalize(Self.fileBytes, owner: try Self.owner())

        let contentType = try #require(await transport.contentType)
        let boundary = try #require(contentType.components(separatedBy: "boundary=").last)
        let body = String(decoding: try #require(await transport.body), as: UTF8.self)

        #expect(contentType.hasPrefix("multipart/form-data; "))
        #expect(body.hasPrefix("--\(boundary)\r\n"))
        #expect(body.hasSuffix("--\(boundary)--\r\n"))
    }

    /// Storage signs `content-length-range` as `[size, size]`, so the file part
    /// must carry exactly the byte count declared to `InitiateExternalUpload`.
    @Test("The file part carries exactly the declared byte count")
    func filePartMatchesDeclaredSize() async throws {
        let transport = RecordingTransport()
        let reserving = StubReserving(states: [.ready])
        let uploader = BlobUploader(reserving: reserving, transport: transport)

        _ = try await uploader.storeThenFinalize(Self.fileBytes, owner: try Self.owner())

        let declared = try #require(await reserving.declaredSizeBytes)
        #expect(declared == Self.fileBytes.count)
        #expect(try await Self.parse(transport).fileByteCount == declared)
    }

    @Test("Parts are CRLF-delimited, not bare newlines")
    func multipartUsesCRLF() async throws {
        let transport = RecordingTransport()
        let uploader = makeUploader(transport: transport, states: [.ready])

        _ = try await uploader.storeThenFinalize(Self.fileBytes, owner: try Self.owner())

        let body = String(decoding: try #require(await transport.body), as: UTF8.self)
        #expect(body.contains("Content-Disposition: form-data; name=\"key\"\r\n\r\n"))
        #expect(!body.contains("form-data; name=\"key\"\n\n"))
    }

    /// The uploader is the write site: bytes that never went through the app's
    /// encoder must still be sanitized, or storage refuses them.
    @Test("Stored bytes are stripped of privacy segments, and the reservation matches")
    func storeStripsPrivacySegments() async throws {
        let transport = RecordingTransport()
        let reserving = StubReserving(states: [.ready])
        let uploader = BlobUploader(reserving: reserving, transport: transport)

        let raw = Self.jpegCarryingComment()
        #expect(raw.count > Self.strippedJPEG.count)

        _ = try await uploader.store(raw, mimeType: "image/jpeg", owner: try Self.owner())

        let sent = try #require(await transport.body)
        #expect(!sent.contains(Data("secret-location".utf8)))
        // The reservation signs the byte count, so it must describe the bytes
        // actually sent — not the ones handed in.
        #expect(await reserving.declaredSizeBytes == Self.strippedJPEG.count)
    }

    // MARK: - Upload failure -

    @Test("A non-2xx from storage surfaces its status")
    func storageFailureCarriesStatus() async throws {
        let transport = RecordingTransport()
        await transport.setResponse(status: 403, body: Data("<Error>SignatureDoesNotMatch</Error>".utf8))
        let uploader = makeUploader(transport: transport, states: [.ready])

        // The status is the whole diagnostic — a bare `ErrorBlob` assertion also
        // passes when the uploader loses it to `.unknown`.
        await #expect(performing: {
            _ = try await uploader.storeThenFinalize(Self.fileBytes, owner: try Self.owner())
        }, throws: { error in
            guard case ErrorBlob.uploadFailed(let status) = error else { return false }
            return status == 403
        })
    }

    /// The upload leg is plain HTTP, so its failures are `URLError`s. They have
    /// to arrive as a blob error, or a dropped connection reports as a defect.
    @Test("A transport failure surfaces as a suppressed network error")
    func transportFailureIsClassifiedAsNetwork() async throws {
        let transport = RecordingTransport()
        await transport.setFailure(URLError(.networkConnectionLost))
        let uploader = makeUploader(transport: transport, states: [.ready])

        await #expect(performing: {
            _ = try await uploader.store(Self.fileBytes, mimeType: "image/jpeg", owner: try Self.owner())
        }, throws: { error in
            guard case ErrorBlob.network = error else { return false }
            return (error as? ErrorBlob)?.reportingLevel == .suppressed
        })
    }

    /// A `URLError` held as an existential bridges to `NSError` and stops
    /// answering to `ServerError`, so the wrapper has to re-cast it concretely —
    /// the generic conformance check alone silently reports network weather as a
    /// defect.
    @Test("A bridged URLError still classifies as network weather")
    func bridgedURLErrorStaysSuppressed() {
        let carried: Error = URLError(.timedOut)

        // Pins the bridge itself: if this ever starts succeeding, the concrete
        // re-cast in ErrorBlob.network is dead weight and should go.
        #expect(carried as? ServerError == nil)
        #expect(ErrorBlob.network(carried).reportingLevel == .suppressed)
    }

    // MARK: - Finalization -

    @Test("Polls until the blob is ready")
    func pollsUntilReady() async throws {
        let reserving = StubReserving(states: [.processing, .processing, .ready])
        let uploader = BlobUploader(
            reserving: reserving,
            transport: RecordingTransport(),
            pollInterval: .milliseconds(1),
            timeout: .seconds(5)
        )

        _ = try await uploader.storeThenFinalize(Self.fileBytes, owner: try Self.owner())

        #expect(await reserving.pollCount == 3)
    }

    @Test("A rejection stops polling and reports why")
    func rejectionIsTerminal() async throws {
        let reserving = StubReserving(states: [.processing, .rejected(.moderation)])
        let uploader = BlobUploader(
            reserving: reserving,
            transport: RecordingTransport(),
            pollInterval: .milliseconds(1),
            timeout: .seconds(5)
        )

        // The reason drives which dialog the user sees, so losing it is a bug a
        // type-only assertion would miss.
        await #expect(performing: {
            _ = try await uploader.storeThenFinalize(Self.fileBytes, owner: try Self.owner())
        }, throws: { error in
            guard case ErrorBlob.rejected(let reason) = error else { return false }
            return reason == .moderation
        })
        #expect(await reserving.pollCount == 2)
    }

    /// Storage can refuse at finalization, before any polling starts — the strip
    /// happens client-side, so a blob rejected for privacy metadata means the
    /// sanitizer let something through.
    @Test("A rejection at completion throws without polling")
    func rejectionAtCompletionSkipsPolling() async throws {
        let reserving = StubReserving(states: [], completion: .rejected(.privacyMetadata))
        let uploader = BlobUploader(
            reserving: reserving,
            transport: RecordingTransport(),
            pollInterval: .milliseconds(1),
            timeout: .seconds(5)
        )

        await #expect(performing: {
            _ = try await uploader.store(Self.fileBytes, mimeType: "image/jpeg", owner: try Self.owner())
        }, throws: { error in
            guard case ErrorBlob.rejected(let reason) = error else { return false }
            return reason == .privacyMetadata
        })
        #expect(await reserving.pollCount == 0)
    }

    @Test("Polling gives up at the deadline")
    func pollingHonoursTheDeadline() async throws {
        let reserving = StubReserving(states: [])
        let uploader = BlobUploader(
            reserving: reserving,
            transport: RecordingTransport(),
            pollInterval: .milliseconds(1),
            timeout: .milliseconds(20)
        )

        await #expect(throws: ErrorBlob.self) {
            _ = try await uploader.storeThenFinalize(Self.fileBytes, owner: try Self.owner())
        }
    }

    /// `store` must hand back the blob without waiting for finalization — that
    /// is what lets a caller whose poll times out resume the same blob instead
    /// of storing a second copy.
    @Test("Storing returns the blob without waiting for finalization")
    func storeReturnsBeforeFinalizing() async throws {
        let reserving = StubReserving(states: [])
        let uploader = BlobUploader(
            reserving: reserving,
            transport: RecordingTransport(),
            pollInterval: .milliseconds(1),
            timeout: .milliseconds(20)
        )

        let blobID = try await uploader.store(Self.fileBytes, mimeType: "image/jpeg", owner: try Self.owner())

        #expect(blobID == StubReserving.blobID)
        #expect(await reserving.pollCount == 0)
    }

    /// A timed-out attempt already stored its bytes, so resuming must poll the
    /// same blob rather than reserve a second upload.
    @Test("Resuming finalization does not re-upload")
    func resumingDoesNotReupload() async throws {
        let transport = RecordingTransport()
        let reserving = StubReserving(states: [.ready])
        let uploader = BlobUploader(
            reserving: reserving,
            transport: transport,
            pollInterval: .milliseconds(1),
            timeout: .seconds(5)
        )

        try await uploader.awaitFinalization(blobID: StubReserving.blobID, owner: try Self.owner())

        #expect(await transport.body == nil)
        #expect(await reserving.reserveCount == 0)
    }

    /// iOS drops the connection when it suspends the app mid-wait; one lost poll is not a failed
    /// upload.
    @Test("A poll lost in transit is retried rather than failing the upload")
    func lostPollIsRetried() async throws {
        let transport = RecordingTransport()
        let reserving = StubReserving(states: [.processing, .ready], lostPolls: 2)
        let uploader = BlobUploader(
            reserving: reserving,
            transport: transport,
            pollInterval: .milliseconds(1),
            timeout: .seconds(5)
        )

        try await uploader.awaitFinalization(blobID: StubReserving.blobID, owner: try Self.owner())

        #expect(await reserving.pollCount == 4)
        #expect(await transport.body == nil)
    }

    @Test("Polls lost in transit still count toward the deadline")
    func lostPollsHonourTheDeadline() async throws {
        // Never three in a row, so only the overall budget ends the wait.
        let reserving = StubReserving(states: [], lostAt: [1, 2, 4, 5])
        let uploader = BlobUploader(
            reserving: reserving,
            transport: RecordingTransport(),
            pollInterval: .milliseconds(1),
            timeout: .milliseconds(5)
        )

        await #expect {
            try await uploader.awaitFinalization(blobID: StubReserving.blobID, owner: try Self.owner())
        } throws: { error in
            guard case ErrorBlob.timedOut = error else { return false }
            return true
        }
        #expect(await reserving.pollCount == 5)
    }

    /// Offline, every poll waits out its RPC deadline, so the overall budget would hold the row at
    /// Sending for minutes.
    @Test("Three polls lost in a row give up as a network failure, well inside the budget")
    func consecutiveLostPollsFailEarly() async throws {
        let reserving = StubReserving(states: [], lostPolls: .max)
        let uploader = BlobUploader(
            reserving: reserving,
            transport: RecordingTransport(),
            pollInterval: .milliseconds(1),
            timeout: .seconds(5)
        )

        await #expect {
            try await uploader.awaitFinalization(blobID: StubReserving.blobID, owner: try Self.owner())
        } throws: { error in
            guard case ErrorBlob.network = error else { return false }
            return true
        }
        #expect(await reserving.pollCount == 3)
    }

    @Test("A poll that gets through starts the lost-poll count again")
    func answeredPollResetsLostStreak() async throws {
        let reserving = StubReserving(states: [.processing, .processing, .ready], lostAt: [1, 2, 4, 5])
        let uploader = BlobUploader(
            reserving: reserving,
            transport: RecordingTransport(),
            pollInterval: .milliseconds(1),
            timeout: .seconds(5)
        )

        try await uploader.awaitFinalization(blobID: StubReserving.blobID, owner: try Self.owner())

        #expect(await reserving.pollCount == 7)
    }

    // MARK: - Fixtures -

    private static let fileBytes = Data(repeating: 0xAB, count: 4096)

    /// A minimal JPEG: SOI, a COM comment carrying personal data, then SOS and
    /// EOI. Enough for the marker walker without pulling in an image encoder.
    private static func jpegCarryingComment() -> Data {
        let comment = Array("secret-location".utf8)
        var data = Data([0xFF, 0xD8])
        data.append(contentsOf: [0xFF, 0xFE])
        let length = comment.count + 2
        data.append(contentsOf: [UInt8(length >> 8), UInt8(length & 0xFF)])
        data.append(contentsOf: comment)
        data.append(contentsOf: [0xFF, 0xDA, 0x00, 0x02])
        data.append(contentsOf: [0xFF, 0xD9])
        return data
    }

    private static let strippedJPEG = Data([0xFF, 0xD8, 0xFF, 0xDA, 0x00, 0x02, 0xFF, 0xD9])

    private static let formFields = [
        "key": "uploads/abc123",
        "Content-Type": "image/jpeg",
        "policy": "eyJleHBpcmF0aW9uIjoi",
        "x-amz-signature": "deadbeef",
    ]

    private static func owner() throws -> KeyPair {
        try #require(KeyPair.generate())
    }

    private func makeUploader(transport: RecordingTransport, states: [BlobState]) -> BlobUploader {
        BlobUploader(
            reserving: StubReserving(states: states),
            transport: transport,
            pollInterval: .milliseconds(1),
            timeout: .seconds(5)
        )
    }

    private struct ParsedBody {
        let names: [String]
        let values: [String: String]
        let fileByteCount: Int
        let file: Data
    }

    private static func parse(_ transport: RecordingTransport) async throws -> ParsedBody {
        let contentType = try #require(await transport.contentType)
        let boundary = try #require(contentType.components(separatedBy: "boundary=").last)
        var body = try #require(await transport.body)

        let closing = Data("--\(boundary)--\r\n".utf8)
        let closingRange = try #require(body.range(of: closing))
        #expect(closingRange.upperBound == body.endIndex)
        body = Data(body[body.startIndex..<closingRange.lowerBound])

        var names: [String] = []
        var values: [String: String] = [:]
        var fileByteCount = 0
        var file = Data()

        for segment in Self.segments(of: body, delimitedBy: "--\(boundary)\r\n") {
            guard let terminator = segment.range(of: Data("\r\n\r\n".utf8)) else { continue }

            let headers = String(decoding: segment[segment.startIndex..<terminator.lowerBound], as: UTF8.self)
            guard let name = headers.components(separatedBy: "name=\"").dropFirst().first?
                .components(separatedBy: "\"").first else { continue }
            names.append(name)

            // Each part is terminated by a CRLF before the next delimiter.
            let payload = Data(segment[terminator.upperBound...].dropLast(2))

            if name == "file" {
                fileByteCount = payload.count
                file = payload
            } else {
                values[name] = String(decoding: payload, as: UTF8.self)
            }
        }

        return ParsedBody(names: names, values: values, fileByteCount: fileByteCount, file: file)
    }

    private static func segments(of body: Data, delimitedBy delimiter: String) -> [Data] {
        let marker = Data(delimiter.utf8)
        var segments: [Data] = []
        var cursor = body.startIndex

        while let range = body.range(of: marker, in: cursor..<body.endIndex) {
            if range.lowerBound > cursor {
                segments.append(Data(body[cursor..<range.lowerBound]))
            }
            cursor = range.upperBound
        }

        if cursor < body.endIndex {
            segments.append(Data(body[cursor..<body.endIndex]))
        }

        return segments
    }
}

// MARK: - Doubles -

/// Records the upload request and returns a canned response. Per-instance state,
/// so suites using it stay parallel-safe.
private actor RecordingTransport: BlobUploading {

    private(set) var url: URL?
    private(set) var contentType: String?
    private(set) var headers: [String: String] = [:]
    private(set) var body: Data?

    private var status = 204
    private var responseBody = Data()
    private var failure: Error?

    func setResponse(status: Int, body: Data) {
        self.status = status
        self.responseBody = body
    }

    func setFailure(_ error: Error) {
        self.failure = error
    }

    func post(
        url: URL,
        contentType: String,
        headers: [String: String],
        body: Data,
        onProgress: @escaping @Sendable (BlobUploadProgress) -> Void
    ) async throws -> (status: Int, body: Data) {
        // Reports the body going out in two halves, as URLSession does in chunks.
        let total = Int64(body.count)
        onProgress(BlobUploadProgress(sentBytes: total / 2, totalBytes: total))
        onProgress(BlobUploadProgress(sentBytes: total, totalBytes: total))

        self.url         = url
        self.contentType = contentType
        self.headers     = headers
        self.body        = body

        if let failure {
            throw failure
        }

        return (status, responseBody)
    }
}

private actor StubReserving: BlobReserving {

    static let blobID = BlobID(uuid: UUID(uuidString: "3f2504e0-4f89-11d3-9a0c-0305e82c3301")!)

    private var states: [BlobState]
    private let completion: BlobState
    private var lostPolls: Int
    private let lostAt: Set<Int>
    private(set) var pollCount = 0
    private(set) var reserveCount = 0
    private(set) var declaredSizeBytes: Int?
    private(set) var declaredMimeType: String?
    private(set) var encryptedFor: ConversationID?

    /// `lostPolls` is how many polls fail in transit before the stub starts answering; `lostAt`
    /// names further polls, counted from 1, that fail in transit.
    init(states: [BlobState], completion: BlobState = .processing, lostPolls: Int = 0, lostAt: Set<Int> = []) {
        self.states = states
        self.completion = completion
        self.lostPolls = lostPolls
        self.lostAt = lostAt
    }

    func initiateExternalUpload(mimeType: String, sizeBytes: Int, encryptedFor: ConversationID?, owner: KeyPair) async throws -> ReservedUpload {
        reserveCount += 1
        declaredSizeBytes = sizeBytes
        declaredMimeType = mimeType
        self.encryptedFor = encryptedFor

        return ReservedUpload(
            blobID: Self.blobID,
            target: UploadTarget(
                url: URL(string: "https://storage.example.com/bucket")!,
                headers: [:],
                formFields: [
                    "key": "uploads/abc123",
                    "Content-Type": "image/jpeg",
                    "policy": "eyJleHBpcmF0aW9uIjoi",
                    "x-amz-signature": "deadbeef",
                ]
            )
        )
    }

    /// `PROCESSING` unless a test says otherwise, so the default path is polling.
    func completeExternalUpload(blobID: BlobID, owner: KeyPair) async throws -> BlobState {
        completion
    }

    func blobState(blobID: BlobID, owner: KeyPair) async throws -> BlobState {
        pollCount += 1
        if lostPolls > 0 || lostAt.contains(pollCount) {
            lostPolls = max(0, lostPolls - 1)
            throw ErrorBlob.network(URLError(.networkConnectionLost))
        }
        return states.isEmpty ? .processing : states.removeFirst()
    }
}

private extension BlobUploader {
    /// What a real caller does: store the bytes, then wait for the server to
    /// finalize them.
    func storeThenFinalize(_ data: Data, owner: KeyPair) async throws -> BlobID {
        let blobID = try await store(data, mimeType: "image/jpeg", owner: owner)
        try await awaitFinalization(blobID: blobID, owner: owner)
        return blobID
    }
}
