//
//  BlobUploading.swift
//  FlipcashCore
//

import Foundation

/// Issues the direct-to-storage upload request.
///
/// The body is an explicit parameter rather than part of a `URLRequest` so
/// callers — and tests — can observe the bytes that go on the wire.
public protocol BlobUploading: Sendable {
    func post(
        url: URL,
        contentType: String,
        headers: [String: String],
        body: Data
    ) async throws -> (status: Int, body: Data)
}

/// The production `BlobUploading`, over a shared `URLSession`.
public struct URLSessionBlobUploader: BlobUploading {

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func post(
        url: URL,
        contentType: String,
        headers: [String: String],
        body: Data
    ) async throws -> (status: Int, body: Data) {

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let (data, response) = try await session.upload(for: request, from: body)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        return (status, data)
    }
}
