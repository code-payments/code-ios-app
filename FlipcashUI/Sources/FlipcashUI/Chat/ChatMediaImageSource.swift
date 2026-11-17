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
    /// The photo's signed download URL, or nil for a photo drawn from the cache alone.
    public let url: URL?
    /// Turns the downloaded blob into the image's plaintext bytes; nil for a plaintext blob.
    public let decrypt: (@Sendable (Data) throws -> Data)?
    /// Tells whoever minted `url` that the CDN refused it (a 403), and returns whether resolving the
    /// photo again will mint a fresh one.
    public let reportRefused: @MainActor @Sendable () -> Bool
    /// Whether the photo's blob is end-to-end encrypted, for its load report.
    let sealed: Bool
    /// The copy of the photo this location draws, or nil for the ORIGINAL a caller asked for by
    /// the photo's own blob. A bubble draws, evicts and reports under this copy's blob.
    public let rendition: MediaRendition?
    /// The caches the photo is read from and written to.
    public let caches: ChatMediaCaches

    public init(
        url: URL,
        caches: ChatMediaCaches,
        decrypt: (@Sendable (Data) throws -> Data)? = nil,
        rendition: MediaRendition? = nil,
        reportRefused: @escaping @MainActor @Sendable () -> Bool = { false }
    ) {
        self.url = url
        self.decrypt = decrypt
        self.reportRefused = reportRefused
        self.sealed = decrypt != nil
        self.rendition = rendition
        self.caches = caches
    }

    private init(sealed: Bool, rendition: MediaRendition?, caches: ChatMediaCaches) {
        self.url = nil
        self.decrypt = nil
        self.reportRefused = { false }
        self.sealed = sealed
        self.rendition = rendition
        self.caches = caches
    }

    /// A photo already in `caches`, which draws without a URL. `sealed` says whether its blob is
    /// end-to-end encrypted, which the cached image alone can't show; `rendition` is the copy found
    /// cached.
    public static func cached(sealed: Bool, rendition: MediaRendition? = nil, in caches: ChatMediaCaches) -> ChatMediaLocation {
        ChatMediaLocation(sealed: sealed, rendition: rendition, caches: caches)
    }
}

/// Where a chat photo's bytes load from, for every view that draws one.
public enum ChatMediaImageSource {

    /// The photo at `location`, cached under its blob rather than the URL. The URL is signed and
    /// minted per fetch, so keying on it would re-download the same photo every session. An
    /// encrypted blob is decrypted before Kingfisher decodes it.
    public static func source(blobID: BlobID?, location: ChatMediaLocation) -> Source {
        let cacheKey = blobID.map(Self.cacheKey(for:)) ?? location.url?.absoluteString ?? ""
        guard let url = location.url else {
            return .provider(CachedOnlyProvider(cacheKey: cacheKey))
        }
        guard let decrypt = location.decrypt else {
            return .network(KF.ImageResource(downloadURL: url, cacheKey: cacheKey))
        }
        return .provider(DecryptingProvider(cacheKey: cacheKey, url: url, decrypt: decrypt, caches: location.caches))
    }

    /// The photo at `location`, from the cache when held, or nil when it fails to load or decrypt.
    /// `blobID` is an ORIGINAL: its callers, Save to Photos and link cards, load nothing smaller.
    @MainActor
    public static func image(blobID: BlobID?, location: ChatMediaLocation, surface: ChatMediaSurface) async -> UIImage? {
        let result = await retrieve(source(blobID: blobID, location: location), options: options(in: location.caches))
        finish(result, blobID: blobID, surface: surface, rendition: .original, location: location)
        return try? result.get().image
    }

    /// Loads `source` through `manager` outside an image view.
    ///
    /// Kingfisher reads a download's timings after decoding it, through a weak reference to the
    /// session task that only the returned ``DownloadTask`` keeps alive. An image view holds that
    /// task itself; here it is held until the result arrives, or the result has no `metrics`.
    @MainActor
    static func retrieve(
        _ source: Source,
        options: KingfisherOptionsInfo,
        manager: KingfisherManager = .shared
    ) async -> Result<RetrieveImageResult, KingfisherError> {
        var task: DownloadTask?
        let result = await withCheckedContinuation { continuation in
            task = manager.retrieveImage(with: source, options: options) {
                continuation.resume(returning: $0)
            }
        }
        withExtendedLifetime(task) {}
        return result
    }

    /// The photo for `blobID` if already held in memory, without loading anything.
    public static func cachedImage(blobID: BlobID, in caches: ChatMediaCaches) -> UIImage? {
        return caches.images.retrieveImageInMemoryCache(forKey: cacheKey(for: blobID))
    }

    /// Whether `blobID`'s photo is cached, in memory or on disk, as drawn by `processor` or full size,
    /// so it can draw from ``ChatMediaLocation/cached(sealed:rendition:in:)`` without a URL. Kingfisher downsamples a
    /// full-size copy on the way out, which the viewer leaves behind.
    public static func isCached(blobID: BlobID, processor: ImageProcessor, in caches: ChatMediaCaches) -> Bool {
        let key = cacheKey(for: blobID)
        return caches.images.imageCachedType(forKey: key, processorIdentifier: processor.identifier).cached
            || caches.images.imageCachedType(forKey: key, processorIdentifier: DefaultImageProcessor.default.identifier).cached
    }

    /// Drops `blobID`'s cached copies after one failed to load, so the next lookup misses and
    /// mints a URL.
    public static func evict(blobID: BlobID, processor: ImageProcessor, in caches: ChatMediaCaches) async {
        let key = cacheKey(for: blobID)
        for identifier in [processor.identifier, DefaultImageProcessor.default.identifier] {
            try? await caches.images.removeImage(forKey: key, processorIdentifier: identifier)
        }
    }

    nonisolated static func cacheKey(for blobID: BlobID) -> String {
        "chat-media-\(blobID.description)"
    }

    /// Writes a photo's downloaded bytes to `cache`'s disk under `blobID` as its full-size copy,
    /// which ``isCached(blobID:processor:in:)`` counts for every processor: Kingfisher downsamples it
    /// for whichever bubble asks. For a download made before any bubble asks, which can't know
    /// whether the photo will draw alone or in a stack.
    nonisolated static func storeFullSize(_ data: Data, blobID: BlobID, in cache: ImageCache) throws {
        try cache.diskStorage.store(value: data, forKey: cacheKey(for: blobID))
    }

    /// Whether a failed load was an encrypted blob that will never decrypt, rather than a fetch
    /// that may succeed later.
    /// Whether the CDN refused the photo's URL (a 403), which a signed URL past its expiry gets.
    public static func isRefused(_ error: KingfisherError) -> Bool {
        switch error {
        case .responseError(reason: .invalidHTTPStatusCode(let response)):
            response.statusCode == 403
        case .imageSettingError(reason: .dataProviderError(_, let underlying)):
            (underlying as? ChatMediaHTTPError)?.status == 403
        default:
            false
        }
    }

    public static func isUndecryptable(_ error: KingfisherError) -> Bool {
        switch error {
        case .imageSettingError(reason: .dataProviderError(_, let underlying)):
            underlying is BlobOpenFailure
        default:
            false
        }
    }

    nonisolated static func storeOriginal(_ data: Data, forKey key: String, in caches: ChatMediaCaches) {
        try? caches.originals.diskStorage.store(value: data, forKey: key)
    }

    /// The photo's bytes as sent, or nil when this device never downloaded them (a staged send, or a
    /// photo cached before originals were kept).
    public static func originalData(blobID: BlobID?, in caches: ChatMediaCaches) -> Data? {
        guard let blobID else { return nil }
        return try? caches.originals.diskStorage.value(forKey: cacheKey(for: blobID))
    }

    /// Empties both caches, in memory and on disk. They hold other people's photos decrypted, so
    /// logout clears them before another account can sign in on the device. Synchronous, unlike
    /// `ImageCache.clearDiskCache`, so nothing survives into the next login.
    public static func clearCaches() {
        for cache in [cache, originals] {
            cache.memoryStorage.removeAll()
            try? cache.diskStorage.removeAll()
        }
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
    public static func options(processor: ImageProcessor? = nil, in caches: ChatMediaCaches) -> KingfisherOptionsInfo {
        var options: KingfisherOptionsInfo = [.targetCache(caches.images)]
        if let processor { options.append(.processor(processor)) }
        return options
    }

    /// Ends a photo load: writes a freshly downloaded photo to disk under its source's key, and logs
    /// how the load went.
    ///
    /// The app-wide `.cacheMemoryOnly` default stops Kingfisher writing it there itself, and the
    /// signed URL changes per fetch, so without this every relaunch or memory trim re-downloads it.
    ///
    /// `rendition` is the role of the copy loaded, nil when the caller can't tell, as a quote can't.
    /// It has no default so each surface states the copy it loads. `location` is the one the load
    /// started from: the photo is written to its caches, and its report is sealed when it is.
    public static func finish(
        _ result: Result<RetrieveImageResult, KingfisherError>,
        blobID: BlobID?,
        surface: ChatMediaSurface,
        rendition: MediaRendition.Role?,
        processor: ImageProcessor? = nil,
        location: ChatMediaLocation
    ) {
        ChatMediaLoadReport(result, blobID: blobID, surface: surface, rendition: rendition, sealed: location.sealed).log()
        guard case .success(let value) = result else { return }
        persist(value.image, cacheType: value.cacheType, forKey: value.source.cacheKey, processor: processor, in: location.caches)
    }

    static func persist(
        _ image: UIImage,
        cacheType: CacheType,
        forKey key: String,
        processor: ImageProcessor?,
        in caches: ChatMediaCaches,
        completion: (@Sendable () -> Void)? = nil
    ) {
        guard cacheType == .none else { return }
        caches.images.store(
            image,
            forKey: key,
            processorIdentifier: processor?.identifier ?? DefaultImageProcessor.default.identifier,
            cacheSerializer: FormatIndicatedCacheSerializer.jpeg,
            toDisk: true
        ) { _ in completion?() }
    }
}

/// A photo held in the cache, loaded without a URL. Kingfisher reads the cache before it asks a
/// provider for data, so this is only asked when the cached copy has gone.
nonisolated struct CachedOnlyProvider: ImageDataProvider {
    struct NotCached: Error {}

    let cacheKey: String

    func data(handler: @escaping @Sendable (Result<Data, any Error>) -> Void) {
        handler(.failure(NotCached()))
    }
}

/// Downloads an end-to-end encrypted chat blob and hands Kingfisher its decrypted bytes.
nonisolated struct DecryptingProvider: ImageDataProvider {
    let cacheKey: String
    let url: URL
    let decrypt: @Sendable (Data) throws -> Data
    /// Where the decrypted bytes are kept as the copy Save to Photos reads.
    let caches: ChatMediaCaches
    /// What this load saw, for its report.
    let trace = ChatMediaLoadTrace()

    var contentURL: URL? { url }

    func data(handler: @escaping @Sendable (Result<Data, any Error>) -> Void) {
        Task {
            do {
                let (blob, response) = try await URLSession.shared.data(from: url, delegate: trace)
                if let response = response as? HTTPURLResponse {
                    trace.update { state in
                        var transfer = state.transfer ?? ChatMediaTransfer()
                        transfer.record(response)
                        state.transfer = transfer
                    }
                    guard (200..<300).contains(response.statusCode) else {
                        throw ChatMediaHTTPError(status: response.statusCode)
                    }
                }
                trace.update { $0.step = .decrypt }
                let clock = ContinuousClock()
                let start = clock.now
                let image = try decrypt(blob)
                let decrypted = clock.now - start
                trace.update {
                    $0.decrypt = decrypted
                    $0.step = .decode
                }
                ChatMediaImageSource.storeOriginal(image, forKey: cacheKey, in: caches)
                // The decoded image is authoritative; bytes that don't decode render as unsupported.
                guard UIImage(data: image) != nil else { throw BlobOpenFailure.undecodable }
                handler(.success(image))
            } catch {
                handler(.failure(error))
            }
        }
    }
}
