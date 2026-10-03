//
//  ChatMediaImageSource.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import UIKit
import FlipcashCore
import Kingfisher

/// Where one chat photo downloads from, and how its bytes become an image.
public struct ChatMediaLocation: Sendable {
    /// The photo's signed download URL.
    public let url: URL
    /// Turns the downloaded blob into the image's plaintext bytes; nil for a plaintext blob.
    public let decrypt: (@Sendable (Data) throws -> Data)?

    public init(url: URL, decrypt: (@Sendable (Data) throws -> Data)? = nil) {
        self.url = url
        self.decrypt = decrypt
    }
}

/// Where a chat photo's bytes load from, for every view that draws one.
public enum ChatMediaImageSource {

    /// The photo at `location`, cached under its blob rather than the URL. The URL is signed and
    /// minted per fetch, so keying on it would re-download the same photo every session. An
    /// encrypted blob is decrypted before Kingfisher decodes it.
    public static func source(blobID: BlobID?, location: ChatMediaLocation) -> Source {
        let cacheKey = blobID.map { "chat-media-\($0.description)" } ?? location.url.absoluteString
        guard let decrypt = location.decrypt else {
            return .network(KF.ImageResource(downloadURL: location.url, cacheKey: cacheKey))
        }
        return .provider(DecryptingProvider(cacheKey: cacheKey, url: location.url, decrypt: decrypt))
    }

    /// Whether a failed load was an encrypted blob that will never decrypt, rather than a fetch
    /// that may succeed later.
    public static func isUndecryptable(_ error: KingfisherError) -> Bool {
        switch error {
        case .imageSettingError(reason: .dataProviderError(_, let underlying)):
            underlying is BlobOpenFailure
        default:
            false
        }
    }

    /// The cache chat photos read and write. A blob's bytes never change, so unlike the app's other
    /// remote images they persist to disk and never expire from memory.
    public static let cache: ImageCache = {
        let cache = ImageCache(name: "chat-media")
        cache.memoryStorage.config.expiration = .never
        cache.diskStorage.config.sizeLimit = 500 * 1024 * 1024
        cache.diskStorage.config.expiration = .days(30)
        return cache
    }()

    /// The options every chat photo load passes, `processor` included when it draws a downsampled copy.
    public static func options(processor: ImageProcessor? = nil) -> KingfisherOptionsInfo {
        var options: KingfisherOptionsInfo = [.targetCache(cache)]
        if let processor { options.append(.processor(processor)) }
        return options
    }

    /// Writes a freshly downloaded photo to disk under `resource`'s key.
    ///
    /// The app-wide `.cacheMemoryOnly` default stops Kingfisher writing it there itself, and the
    /// signed URL changes per fetch, so without this every relaunch or memory trim re-downloads it.
    public static func persist(
        _ result: Result<RetrieveImageResult, KingfisherError>,
        processor: ImageProcessor? = nil
    ) {
        guard case .success(let value) = result else { return }
        persist(value.image, cacheType: value.cacheType, forKey: value.source.cacheKey, processor: processor)
    }

    static func persist(
        _ image: UIImage,
        cacheType: CacheType,
        forKey key: String,
        processor: ImageProcessor?,
        completion: (@Sendable () -> Void)? = nil
    ) {
        guard cacheType == .none else { return }
        cache.store(
            image,
            forKey: key,
            processorIdentifier: processor?.identifier ?? DefaultImageProcessor.default.identifier,
            cacheSerializer: FormatIndicatedCacheSerializer.jpeg,
            toDisk: true
        ) { _ in completion?() }
    }
}

/// Downloads an end-to-end encrypted chat blob and hands Kingfisher its decrypted bytes.
private struct DecryptingProvider: ImageDataProvider {
    let cacheKey: String
    let url: URL
    let decrypt: @Sendable (Data) throws -> Data

    var contentURL: URL? { url }

    func data(handler: @escaping @Sendable (Result<Data, any Error>) -> Void) {
        Task {
            do {
                let (blob, response) = try await URLSession.shared.data(from: url)
                if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
                    throw URLError(.badServerResponse)
                }
                let image = try decrypt(blob)
                // The decoded image is authoritative; bytes that don't decode render as unsupported.
                guard UIImage(data: image) != nil else { throw BlobOpenFailure.undecodable }
                handler(.success(image))
            } catch {
                handler(.failure(error))
            }
        }
    }
}
