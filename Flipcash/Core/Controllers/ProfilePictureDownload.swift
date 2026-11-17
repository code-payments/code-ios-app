//
//  ProfilePictureDownload.swift
//  Flipcash
//

import UIKit
import FlipcashCore

/// How a profile picture's bytes are read from ``BlobCache`` and downloaded. Shared by
/// ``ProfileAvatarStore`` and ``ProfilePictureLoader``, which write the same cache.
///
/// Only bytes that decode as an image are cached or served. An error body cached under a blob id
/// draws nothing, and since a blob never changes, nothing would fetch it again.
enum ProfilePictureDownload {

    /// Why a download produced no picture.
    enum Failure: Error {
        /// The server answered with a non-2xx status.
        case status(Int)
        /// The body did not decode as an image.
        case notAnImage
    }

    /// The bytes cached for `blobID` if they decode as an image. Bytes that don't are evicted, so the
    /// caller downloads the picture again.
    static func cachedImageData(for blobID: BlobID, in cache: BlobCache) -> Data? {
        guard let data = cache.data(for: blobID) else { return nil }
        guard isImage(data) else {
            cache.remove(blobID)
            return nil
        }
        return data
    }

    /// Downloads a picture's bytes, or returns nil when `mintURL` has no URL for it.
    ///
    /// A 403 is how CloudFront refuses an expired signature, so on one this mints a fresh URL and
    /// tries once more.
    ///
    /// - Throws: ``Failure`` for an error status or a body that is not an image, or the transport's
    ///   own error.
    static func imageData(
        mintURL: () async throws -> URL?,
        fetch: (URL) async throws -> (Data, URLResponse)
    ) async throws -> Data? {
        guard let url = try await mintURL() else { return nil }
        do {
            return try await imageData(at: url, fetch: fetch)
        } catch Failure.status(403) {
            guard let url = try await mintURL() else { return nil }
            return try await imageData(at: url, fetch: fetch)
        }
    }

    private static func imageData(
        at url: URL,
        fetch: (URL) async throws -> (Data, URLResponse)
    ) async throws -> Data {
        let (data, response) = try await fetch(url)
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            throw Failure.status(status)
        }
        guard isImage(data) else { throw Failure.notAnImage }
        return data
    }

    /// The same test `ContactAvatarView` applies before drawing the bytes.
    private static func isImage(_ data: Data) -> Bool {
        UIImage(data: data) != nil
    }
}
