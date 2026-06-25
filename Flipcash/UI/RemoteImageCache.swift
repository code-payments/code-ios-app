//
//  RemoteImageCache.swift
//  Code
//

import Foundation
import Kingfisher

enum RemoteImageCache {

    /// Configures remote-image caching so an image's lifetime follows the server's HTTP
    /// headers — `Cache-Control`/`Expires` for freshness, `ETag` for revalidation —
    /// instead of being cached indefinitely. Call once at launch.
    static func install() {
        // The system URLCache is the persistent, revalidating layer: it stores responses
        // on disk and issues conditional GETs (`If-None-Match`) so a changed image is
        // refetched rather than served forever. Kingfisher's downloader defaults to an
        // `.ephemeral` session with no URLCache, so give it one.
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 20 * 1024 * 1024,
            diskCapacity: 300 * 1024 * 1024
        )
        ImageDownloader.default.sessionConfiguration = configuration

        KingfisherManager.shared.defaultOptions += [
            // Kingfisher builds every request with `.reloadIgnoringLocalCacheData`, which
            // bypasses the URLCache. Restore protocol cache policy so the URLCache and its
            // ETag revalidation are actually consulted.
            .requestModifier(AnyModifier { request in
                var request = request
                request.cachePolicy = .useProtocolCachePolicy
                return request
            }),
            // Keep Kingfisher's in-memory decoded cache (smooth, flicker-free scrolling)
            // but not its disk cache: a second persistent layer would shadow the URLCache
            // and pin stale images. Persistence lives in the URLCache above.
            .cacheMemoryOnly,
        ]

        clearLegacyDiskCacheIfNeeded()
    }

    /// `.cacheMemoryOnly` stops future disk writes but not reads, so an image cached by a
    /// prior build still serves from Kingfisher's disk and masks the URLCache. Purge it
    /// once so existing installs pick up the current server image.
    private static func clearLegacyDiskCacheIfNeeded() {
        guard UserDefaults.didClearLegacyImageDiskCache != true else { return }
        ImageCache.default.clearDiskCache {
            Task { @MainActor in UserDefaults.didClearLegacyImageDiskCache = true }
        }
    }
}

// MARK: - UserDefaults -

extension UserDefaults {

    @Defaults(.didClearLegacyImageDiskCache)
    fileprivate static var didClearLegacyImageDiskCache: Bool?
}
