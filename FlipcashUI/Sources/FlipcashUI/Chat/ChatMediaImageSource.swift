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
        let cacheKey = blobID.map(Self.cacheKey(for:)) ?? location.url.absoluteString
        guard let decrypt = location.decrypt else {
            return .network(KF.ImageResource(downloadURL: location.url, cacheKey: cacheKey))
        }
        return .provider(DecryptingProvider(cacheKey: cacheKey, url: location.url, decrypt: decrypt))
    }

    /// The photo at `location`, from the cache when held, or nil when it fails to load or decrypt.
    @MainActor
    public static func image(blobID: BlobID?, location: ChatMediaLocation) async -> UIImage? {
        let source = source(blobID: blobID, location: location)
        guard let result = try? await KingfisherManager.shared.retrieveImage(with: source, options: options()) else {
            return nil
        }
        persist(.success(result))
        return result.image
    }

    /// The photo for `blobID` if already held in memory, without loading anything.
    public static func cachedImage(blobID: BlobID) -> UIImage? {
        cache.retrieveImageInMemoryCache(forKey: cacheKey(for: blobID))
    }

    private static func cacheKey(for blobID: BlobID) -> String {
        "chat-media-\(blobID.description)"
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

    /// The decrypted bytes of each downloaded photo exactly as sent. The main cache holds only a
    /// decoded copy re-serialized as JPEG, which would turn a PNG or HEIC into a lossy JPEG on save.
    nonisolated static let originals: ImageCache = {
        let cache = ImageCache(name: "chat-media-originals")
        cache.diskStorage.config.sizeLimit = 500 * 1024 * 1024
        cache.diskStorage.config.expiration = .days(30)
        return cache
    }()

    nonisolated static func storeOriginal(_ data: Data, forKey key: String) {
        try? originals.diskStorage.store(value: data, forKey: key)
    }

    /// The photo's bytes as sent, or nil when this device never downloaded them (a staged send, or a
    /// photo cached before originals were kept).
    public static func originalData(blobID: BlobID?) -> Data? {
        guard let blobID else { return nil }
        return try? originals.diskStorage.value(forKey: cacheKey(for: blobID))
    }

    /// Whether `data` is an image Photos takes as-is, read from its leading bytes rather than any
    /// label the cache or URL carries.
    public static func isLibraryImage(_ data: Data) -> Bool {
        let b = [UInt8](data.prefix(12))
        guard b.count >= 12 else { return false }
        if b[0] == 0xFF, b[1] == 0xD8, b[2] == 0xFF { return true }                       // JPEG
        if b[0...3] == [0x89, 0x50, 0x4E, 0x47] { return true }                           // PNG
        if b[0...3] == [0x47, 0x49, 0x46, 0x38] { return true }                           // GIF
        if b[0...3] == [0x52, 0x49, 0x46, 0x46], b[8...11] == [0x57, 0x45, 0x42, 0x50] { return true } // WebP
        if b[4...7] == [0x66, 0x74, 0x79, 0x70] {                                         // ISO BMFF: HEIC
            let brand = String(decoding: b[8...11], as: UTF8.self)
            return ["heic", "heix", "hevc", "hevx", "heim", "heis", "mif1", "msf1"].contains(brand)
        }
        return false
    }

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
                ChatMediaImageSource.storeOriginal(image, forKey: cacheKey)
                // The decoded image is authoritative; bytes that don't decode render as unsupported.
                guard UIImage(data: image) != nil else { throw BlobOpenFailure.undecodable }
                handler(.success(image))
            } catch {
                handler(.failure(error))
            }
        }
    }
}
