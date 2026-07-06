//
//  LinkMetadataCache.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import LinkPresentation

/// Fetches web-link preview metadata. Abstracted so the cache can be unit-tested with a stub instead of
/// hitting the network.
protocol LinkMetadataFetching: Sendable {
    func fetch(_ url: URL) async throws -> SendableLinkMetadata
}

/// Carries an `LPLinkMetadata` across concurrency domains. `LPLinkMetadata` conforms to
/// `NSSecureCoding` and is safe to hand off once fully populated by the provider.
nonisolated struct SendableLinkMetadata: @unchecked Sendable {
    let value: LPLinkMetadata
    init(_ value: LPLinkMetadata) { self.value = value }
}

/// The real fetcher: one `LPMetadataProvider` per call (they are single-use).
struct LPMetadataFetcher: LinkMetadataFetching {
    func fetch(_ url: URL) async throws -> SendableLinkMetadata {
        let provider = LPMetadataProvider()
        return try await withCheckedThrowingContinuation { continuation in
            provider.startFetchingMetadata(for: url) { metadata, error in
                if let metadata {
                    continuation.resume(returning: SendableLinkMetadata(metadata))
                } else {
                    continuation.resume(throwing: error ?? URLError(.badServerResponse))
                }
            }
        }
    }
}

/// Fetches and caches link preview metadata by URL, deduping in-flight requests so N cells showing the
/// same link trigger one fetch. Main-actor: it serves the (main-actor) chat cells. Vends
/// `SendableLinkMetadata` rather than the raw `LPLinkMetadata` so results can cross `async let`
/// boundaries. Failures are not cached, so a later display can retry.
@MainActor
public final class LinkMetadataCache {

    public static let shared = LinkMetadataCache(fetcher: LPMetadataFetcher())

    /// Wraps `SendableLinkMetadata` in a class so it can live in `NSCache`, which only stores reference
    /// types.
    private final class MetadataBox {
        let value: SendableLinkMetadata
        init(_ value: SendableLinkMetadata) { self.value = value }
    }

    private let fetcher: LinkMetadataFetching
    private let cache = NSCache<NSURL, MetadataBox>()
    private var inFlight: [URL: Task<SendableLinkMetadata?, Never>] = [:]

    /// Decoded hero images keyed by the REQUESTED url (not the metadata's resolved url, which can
    /// differ after a redirect) — so a cell that already knows its url can look up the image before
    /// metadata is even fetched again. Evicts under memory pressure.
    private let images = NSCache<NSURL, UIImage>()

    init(fetcher: LinkMetadataFetching) {
        self.fetcher = fetcher
    }

    /// Metadata already in the cache, without fetching. Nil on a miss.
    func cachedValue(for url: URL) -> SendableLinkMetadata? {
        cache.object(forKey: url as NSURL)?.value
    }

    /// Cached metadata, or a fresh fetch. Returns nil on failure (the caller then shows no card).
    func metadata(for url: URL) async -> SendableLinkMetadata? {
        if let cached = cachedValue(for: url) { return cached }
        if let existing = inFlight[url] { return await existing.value }

        let task = Task<SendableLinkMetadata?, Never> { [fetcher] in
            try? await fetcher.fetch(url)
        }
        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        if let result { cache.setObject(MetadataBox(result), forKey: url as NSURL) }
        return result
    }

    /// The hero image for `url`, decoded from `metadata`'s image (or icon) provider. Cached by the
    /// requested url so a later call for the same url is a cache hit even without re-fetching metadata.
    /// Nil when the metadata carries no image/icon provider, or decoding fails.
    func image(for url: URL, from metadata: LPLinkMetadata) async -> UIImage? {
        let key = url as NSURL
        if let cached = images.object(forKey: key) { return cached }
        guard let provider = metadata.imageProvider ?? metadata.iconProvider else { return nil }
        guard let image = try? await Self.loadImage(from: provider) else { return nil }
        images.setObject(image, forKey: key)
        return image
    }

    /// Warms the cache for `url` without waiting on the result — lets metadata land before a cell
    /// displays, so the card's title and hero image fill in sooner instead of each card starting its own
    /// fetch on first configure.
    func prefetch(_ url: URL) {
        guard cachedValue(for: url) == nil else { return }
        Task { _ = await metadata(for: url) }
    }

    private static func loadImage(from provider: NSItemProvider) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadObject(ofClass: UIImage.self) { object, error in
                if let image = object as? UIImage {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: error ?? URLError(.cannotDecodeContentData))
                }
            }
        }
    }
}
#endif
