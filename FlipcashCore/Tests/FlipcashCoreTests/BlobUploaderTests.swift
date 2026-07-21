//
//  BlobUploaderTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("Blob upload")
struct BlobUploaderTests {

    // MARK: - Multipart body -

    @Test("Signed policy fields come first, the file last")
    func multipartOrdersFileLast() async throws {
        let transport = RecordingTransport()
        let uploader = makeUploader(transport: transport, states: [.ready])

        _ = try await uploader.upload(Self.fileBytes, mimeType: "image/jpeg", owner: try Self.owner())

        let parsed = try await Self.parse(transport)
        #expect(parsed.names.last == "file")
        #expect(Array(parsed.names.dropLast()) == ["Content-Type", "key", "policy", "x-amz-signature"])
    }

    @Test("Signed policy fields reach storage verbatim")
    func multipartPreservesSignedFields() async throws {
        let transport = RecordingTransport()
        let uploader = makeUploader(transport: transport, states: [.ready])

        _ = try await uploader.upload(Self.fileBytes, mimeType: "image/jpeg", owner: try Self.owner())

        let parsed = try await Self.parse(transport)
        for (name, value) in Self.formFields {
            #expect(parsed.values[name] == value)
        }
    }

    @Test("The boundary declared in Content-Type is the one delimiting the body")
    func multipartBoundaryMatchesContentType() async throws {
        let transport = RecordingTransport()
        let uploader = makeUploader(transport: transport, states: [.ready])

        _ = try await uploader.upload(Self.fileBytes, mimeType: "image/jpeg", owner: try Self.owner())

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

        _ = try await uploader.upload(Self.fileBytes, mimeType: "image/jpeg", owner: try Self.owner())

        let declared = try #require(await reserving.declaredSizeBytes)
        #expect(declared == Self.fileBytes.count)
        #expect(try await Self.parse(transport).fileByteCount == declared)
    }

    @Test("Parts are CRLF-delimited, not bare newlines")
    func multipartUsesCRLF() async throws {
        let transport = RecordingTransport()
        let uploader = makeUploader(transport: transport, states: [.ready])

        _ = try await uploader.upload(Self.fileBytes, mimeType: "image/jpeg", owner: try Self.owner())

        let body = String(decoding: try #require(await transport.body), as: UTF8.self)
        #expect(body.contains("Content-Disposition: form-data; name=\"key\"\r\n\r\n"))
        #expect(!body.contains("form-data; name=\"key\"\n\n"))
    }

    // MARK: - Upload failure -

    @Test("A non-2xx from storage surfaces its status")
    func storageFailureCarriesStatus() async throws {
        let transport = RecordingTransport()
        await transport.setResponse(status: 403, body: Data("<Error>SignatureDoesNotMatch</Error>".utf8))
        let uploader = makeUploader(transport: transport, states: [.ready])

        await #expect(throws: ErrorBlob.self) {
            _ = try await uploader.upload(Self.fileBytes, mimeType: "image/jpeg", owner: try Self.owner())
        }
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

        _ = try await uploader.upload(Self.fileBytes, mimeType: "image/jpeg", owner: try Self.owner())

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

        await #expect(throws: ErrorBlob.self) {
            _ = try await uploader.upload(Self.fileBytes, mimeType: "image/jpeg", owner: try Self.owner())
        }
        #expect(await reserving.pollCount == 2)
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
            _ = try await uploader.upload(Self.fileBytes, mimeType: "image/jpeg", owner: try Self.owner())
        }
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

    // MARK: - Fixtures -

    private static let fileBytes = Data(repeating: 0xAB, count: 4096)

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
            } else {
                values[name] = String(decoding: payload, as: UTF8.self)
            }
        }

        return ParsedBody(names: names, values: values, fileByteCount: fileByteCount)
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

    func setResponse(status: Int, body: Data) {
        self.status = status
        self.responseBody = body
    }

    func post(url: URL, contentType: String, headers: [String: String], body: Data) async throws -> (status: Int, body: Data) {
        self.url         = url
        self.contentType = contentType
        self.headers     = headers
        self.body        = body

        return (status, responseBody)
    }
}

private actor StubReserving: BlobReserving {

    static let blobID = BlobID(uuid: UUID(uuidString: "3f2504e0-4f89-11d3-9a0c-0305e82c3301")!)

    private var states: [BlobState]
    private(set) var pollCount = 0
    private(set) var reserveCount = 0
    private(set) var declaredSizeBytes: Int?

    init(states: [BlobState]) {
        self.states = states
    }

    func initiateExternalUpload(mimeType: String, sizeBytes: Int, owner: KeyPair) async throws -> ReservedUpload {
        reserveCount += 1
        declaredSizeBytes = sizeBytes

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

    /// Always `PROCESSING`, so every test exercises the polling path.
    func completeExternalUpload(blobID: BlobID, owner: KeyPair) async throws -> BlobState {
        .processing
    }

    func blobState(blobID: BlobID, owner: KeyPair) async throws -> BlobState {
        pollCount += 1
        return states.isEmpty ? .processing : states.removeFirst()
    }
}
