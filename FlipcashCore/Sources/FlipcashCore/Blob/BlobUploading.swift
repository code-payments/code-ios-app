//
//  BlobUploading.swift
//  FlipcashCore
//

import Foundation

/// Issues the direct-to-storage upload request.
///
/// The body is an explicit parameter rather than part of a `URLRequest` so
/// callers — and tests — can observe the bytes that go on the wire.
protocol BlobUploading: Sendable {
    func post(
        url: URL,
        contentType: String,
        headers: [String: String],
        body: Data,
        onProgress: @escaping @Sendable (BlobUploadProgress) -> Void
    ) async throws -> (status: Int, body: Data)
}

/// How much of an upload's request body has gone out.
public struct BlobUploadProgress: Sendable, Equatable {
    /// Bytes of the request body sent so far.
    public let sentBytes: Int64
    /// The request body's full length.
    public let totalBytes: Int64

    public init(sentBytes: Int64, totalBytes: Int64) {
        self.sentBytes  = sentBytes
        self.totalBytes = totalBytes
    }

    /// The share of the body sent, from 0 to 1, or nil when the length is unknown.
    public var fraction: Double? {
        guard totalBytes > 0 else { return nil }
        return min(max(Double(sentBytes) / Double(totalBytes), 0), 1)
    }
}

/// The production `BlobUploading`, over a shared `URLSession`.
struct URLSessionBlobUploader: BlobUploading {

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func post(
        url: URL,
        contentType: String,
        headers: [String: String],
        body: Data,
        onProgress: @escaping @Sendable (BlobUploadProgress) -> Void
    ) async throws -> (status: Int, body: Data) {

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        // The body's own length, since `totalBytesExpectedToSend` can be unknown (-1).
        let delegate = UploadProgressDelegate(totalBytes: Int64(body.count), onProgress: onProgress)
        let (data, response) = try await session.upload(for: request, from: body, delegate: delegate)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        return (status, data)
    }
}

/// Forwards one upload task's sent-byte counts.
private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, Sendable {

    private let totalBytes: Int64
    private let onProgress: @Sendable (BlobUploadProgress) -> Void

    init(totalBytes: Int64, onProgress: @escaping @Sendable (BlobUploadProgress) -> Void) {
        self.totalBytes = totalBytes
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        onProgress(BlobUploadProgress(sentBytes: totalBytesSent, totalBytes: totalBytes))
    }
}
