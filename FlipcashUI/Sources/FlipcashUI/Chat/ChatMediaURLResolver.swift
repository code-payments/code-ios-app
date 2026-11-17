//
//  ChatMediaURLResolver.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore
import Kingfisher

private let logger = Logger(label: "flipcash.chat-media")

/// Resolves and caches the signed download URL for each photo in one conversation.
///
/// It is the only path from a photo row to the network, so a row that draws only its BlurHash — a
/// redacted photo, or any photo while the viewer previews a group they have not joined — never
/// fetches. Not fetching is what keeps that state from being a blur over bytes already on the device.
public final class ChatMediaURLResolver {

    /// Mints a download URL for a blob, or returns nil when the server has none to give.
    public typealias Fetch = @MainActor (BlobID) async throws -> BlobDownloadLink?
    /// Decrypts an end-to-end encrypted blob into its image bytes, throwing when it fails to
    /// authenticate or is not the declared length.
    public typealias BlobDecrypt = @Sendable (Data, BlobID, SealedBlob) throws -> Data
    /// Builds the conversation's blob decryption, or returns nil while it can't be (its key is not
    /// known yet).
    public typealias FetchDecrypt = @MainActor () async -> BlobDecrypt?

    private let fetch: Fetch
    private let fetchDecrypt: FetchDecrypt
    /// The current time, read to tell whether a cached URL has expired.
    private let now: () -> Date
    private var cache: [BlobID: MintedURL] = [:]
    /// Blobs whose URL the CDN refused, so the next mint for each is the retry.
    private var refusedBlobs: Set<BlobID> = []
    /// Everyone waiting on a blob's fetch, called with its URL, or nil when the fetch failed.
    private var waiters: [BlobID: [(URL?) -> Void]] = [:]
    private var decrypt: BlobDecrypt?
    /// Everyone waiting on the decryption, or nil when no fetch of it is in flight.
    private var decryptWaiters: [(BlobDecrypt?) -> Void]?

    /// How long before its expiry a URL stops being handed out, so a download started on it has
    /// time to finish. Also the shortest a URL is kept, so one that arrives already expired by the
    /// device's clock is used rather than minted again on every redraw.
    static let expiryMargin: TimeInterval = 30

    /// One minted URL and how long to hand it out.
    private struct MintedURL {
        let url: URL
        /// When to stop handing it out, or nil when the server sent no expiry.
        let usableUntil: Date?
        /// Whether it was minted because the CDN refused the one before it.
        let afterRefusal: Bool
    }

    /// The caches every location this hands out reads and writes.
    private let caches: ChatMediaCaches
    /// Where the notification extension leaves the photos it downloaded for a push.
    private let pushedPhotos: BlobCache
    /// Everyone waiting on a blob's move from ``pushedPhotos`` into the chat cache, called with
    /// whether it landed.
    private var importWaiters: [BlobID: [(Bool) -> Void]] = [:]

    /// - Parameters:
    ///   - caches: the chat photo caches, ``ChatMediaCaches/shared`` in the app.
    ///   - pushedPhotos: the notification extension's photos, read before a mint,
    ///   ``BlobCache/chatPhotos`` in the app.
    ///   Both are injected so tests run against a temporary directory.
    public init(
        fetch: @escaping Fetch,
        decrypt: @escaping FetchDecrypt = { nil },
        now: @escaping () -> Date = Date.init,
        caches: ChatMediaCaches,
        pushedPhotos: BlobCache
    ) {
        self.fetch = fetch
        self.fetchDecrypt = decrypt
        self.now = now
        self.caches = caches
        self.pushedPhotos = pushedPhotos
    }

    /// Where to draw `media` from, or nil for now.
    ///
    /// A BlurHash-only row returns nil without fetching. With `load`, the row draws `load`'s copy of
    /// the photo: one already cached as `load`'s processor, or full size, draws from
    /// ``ChatMediaLocation/cached(sealed:rendition:in:)`` without fetching, and so does the ORIGINAL
    /// when it is the copy cached, as it is for a photo drawn before renditions were loaded. Either
    /// copy left by the notification extension in `pushedPhotos` is moved into the cache first, then
    /// drawn the same way. Without `load` the ORIGINAL is fetched. A URL cache miss starts at most one fetch per blob and calls
    /// `onResolved` when it lands so the caller can redraw the row; a failed fetch leaves the row on
    /// its BlurHash, and the next call tries again. An encrypted photo also waits on the chat's
    /// decryption.
    public func location(
        for media: ChatMediaContent,
        canReact: Bool,
        drawing load: ChatMediaBubbleLoad? = nil,
        onResolved: @escaping (ChatMediaLocation) -> Void
    ) -> ChatMediaLocation? {
        guard !ChatMediaCell.isBlurhashOnly(media, canReact: canReact),
              let blobID = media.blobID else { return nil }
        guard let load else {
            return resolve(blobID, sealed: media.sealed) { $0.map(onResolved) }
        }
        let fallback = load.rendition.role == .original ? nil : media.original
        let copies = [load.rendition, fallback].compactMap(\.self)
        let sealed = media.sealed != nil
        for copy in copies where ChatMediaImageSource.isCached(blobID: copy.blobID, processor: load.processor, in: caches) {
            return .cached(sealed: sealed, rendition: copy, in: caches)
        }
        if let pushed = copies.first(where: { pushedPhotos.holds($0.blobID) }) {
            importPushed(pushed, sealed: sealed) { [weak self, caches] imported in
                guard imported else {
                    // The bytes went missing or would not write: fetch as if none were pushed.
                    if let location = self?.resolve(load.rendition.blobID, sealed: media.sealed, rendition: load.rendition, completion: { $0.map(onResolved) }) {
                        onResolved(location)
                    }
                    return
                }
                onResolved(.cached(sealed: sealed, rendition: pushed, in: caches))
            }
            return nil
        }
        return resolve(load.rendition.blobID, sealed: media.sealed, rendition: load.rendition) { $0.map(onResolved) }
    }

    /// Queues `completion` on the one move of `copy` from ``pushedPhotos`` into the chat cache,
    /// starting it if none is in flight. The disk work runs off the main thread.
    private func importPushed(_ copy: MediaRendition, sealed: Bool, completion: @escaping (Bool) -> Void) {
        let blobID = copy.blobID
        let isFirst = importWaiters[blobID] == nil
        importWaiters[blobID, default: []].append(completion)
        guard isFirst else { return }
        let pushed = pushedPhotos
        let caches = caches
        Task {
            let imported = await Task.detached(priority: .userInitiated) {
                Self.movePushed(blobID, sealed: sealed, from: pushed, into: caches)
            }.value
            logger.info("Chat photo taken from push", metadata: [
                "blobId": "\(blobID)",
                "rendition": "\(copy.role)",
                "outcome": "\(imported ? "ok" : "failed")",
            ])
            let completions = importWaiters.removeValue(forKey: blobID) ?? []
            for completion in completions { completion(imported) }
        }
    }

    /// Writes `blobID`'s bytes from `pushed` into `cache` as its full-size copy, then drops them from
    /// `pushed`; false when they are gone or would not write. The extension decrypts a sealed photo
    /// before storing it, so its bytes are also kept as the copy Save to Photos reads.
    nonisolated private static func movePushed(_ blobID: BlobID, sealed: Bool, from pushed: BlobCache, into caches: ChatMediaCaches) -> Bool {
        guard let data = pushed.data(for: blobID) else { return false }
        do {
            try ChatMediaImageSource.storeFullSize(data, blobID: blobID, in: caches.images)
        } catch {
            return false
        }
        if sealed {
            ChatMediaImageSource.storeOriginal(data, forKey: ChatMediaImageSource.cacheKey(for: blobID), in: caches)
        }
        pushed.remove(blobID)
        return true
    }

    /// Where to draw `media` from, waiting for the fetch; nil when it may not draw or the fetch
    /// failed. Follows the same rules as the callback form.
    public func location(for media: ChatMediaContent, canReact: Bool) async -> ChatMediaLocation? {
        guard !ChatMediaCell.isBlurhashOnly(media, canReact: canReact),
              let blobID = media.blobID else { return nil }
        return await location(of: blobID, sealed: media.sealed)
    }

    /// Where to draw a quoted photo's thumbnail from, or nil for now, sharing the photo row's cache.
    ///
    /// Nil without fetching for anything but a photo whose bytes the viewer may see: a quote of text,
    /// cash, or an unavailable original, a redacted photo (``ChatQuote/Kind/media(thumbnailBlobID:sealed:)``
    /// carries no blob), or any quote while the viewer previews a group they have not joined.
    public func thumbnailLocation(
        for kind: ChatQuote.Kind,
        canReact: Bool,
        onResolved: @escaping (ChatMediaLocation) -> Void
    ) -> ChatMediaLocation? {
        guard let (blobID, sealed) = Self.thumbnailBlob(for: kind, canReact: canReact) else { return nil }
        return resolve(blobID, sealed: sealed) { $0.map(onResolved) }
    }

    /// Where to draw a quoted photo's thumbnail from, waiting for the fetch; nil when there is none
    /// to draw or the fetch failed. Follows the same rules as the callback form.
    public func thumbnailLocation(for kind: ChatQuote.Kind, canReact: Bool) async -> ChatMediaLocation? {
        guard let (blobID, sealed) = Self.thumbnailBlob(for: kind, canReact: canReact) else { return nil }
        return await location(of: blobID, sealed: sealed)
    }

    /// Where to draw `attachment` from, waiting for the fetch; nil when it has no blob or the fetch
    /// failed. A link preview's image goes through here, sharing the photo rows' cache.
    public func location(for attachment: MediaAttachment) async -> ChatMediaLocation? {
        guard let blobID = attachment.blobID else { return nil }
        return await location(of: blobID, sealed: attachment.sealed)
    }

    private func location(of blobID: BlobID, sealed: SealedBlob?) async -> ChatMediaLocation? {
        await withCheckedContinuation { continuation in
            var resumed = false
            let immediate = resolve(blobID, sealed: sealed) { location in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: location)
            }
            if let immediate, !resumed {
                resumed = true
                continuation.resume(returning: immediate)
            }
        }
    }

    private static func thumbnailBlob(for kind: ChatQuote.Kind, canReact: Bool) -> (BlobID, SealedBlob?)? {
        switch kind {
        case .media(let thumbnailBlobID, let sealed):
            guard canReact, let thumbnailBlobID else { return nil }
            return (thumbnailBlobID, sealed)
        case .text, .cash, .unavailable:
            return nil
        }
    }

    /// The location for `blobID` when everything it needs is cached, or nil after queueing
    /// `completion` on the fetches it still waits on.
    /// `rendition` is the copy `blobID` is, carried on the location so its drawer can tell.
    private func resolve(
        _ blobID: BlobID,
        sealed: SealedBlob?,
        rendition: MediaRendition? = nil,
        completion: @escaping (ChatMediaLocation?) -> Void
    ) -> ChatMediaLocation? {
        if let url = usableURL(blobID) {
            guard let sealed else { return location(url: url, blobID: blobID, rendition: rendition, sealed: nil, decrypt: nil) }
            if let decrypt { return location(url: url, blobID: blobID, rendition: rendition, sealed: sealed, decrypt: decrypt) }
            awaitDecrypt { [weak self] decrypt in
                completion(decrypt.flatMap { self?.location(url: url, blobID: blobID, rendition: rendition, sealed: sealed, decrypt: $0) })
            }
            return nil
        }
        fetchURL(blobID) { [weak self] url in
            guard let self, let url else { return completion(nil) }
            guard let sealed else { return completion(location(url: url, blobID: blobID, rendition: rendition, sealed: nil, decrypt: nil)) }
            if let decrypt {
                return completion(location(url: url, blobID: blobID, rendition: rendition, sealed: sealed, decrypt: decrypt))
            }
            awaitDecrypt { [weak self] decrypt in
                completion(decrypt.flatMap { self?.location(url: url, blobID: blobID, rendition: rendition, sealed: sealed, decrypt: $0) })
            }
        }
        return nil
    }

    /// `blobID`'s cached URL while it is still safe to start a download on, dropping it once not.
    private func usableURL(_ blobID: BlobID) -> URL? {
        guard let minted = cache[blobID] else { return nil }
        if let usableUntil = minted.usableUntil, now() >= usableUntil {
            cache[blobID] = nil
            return nil
        }
        return minted.url
    }

    private func location(url: URL, blobID: BlobID, rendition: MediaRendition?, sealed: SealedBlob?, decrypt: BlobDecrypt?) -> ChatMediaLocation {
        var open: (@Sendable (Data) throws -> Data)?
        if let sealed, let decrypt {
            open = { try decrypt($0, blobID, sealed) }
        }
        return ChatMediaLocation(
            url: url,
            caches: caches,
            decrypt: open,
            rendition: rendition,
            reportRefused: { [weak self] in self?.refuse(url, blobID: blobID) ?? false }
        )
    }

    /// Drops `url` after the CDN refused it, so the next lookup mints again, and returns whether it
    /// will. Only the URL still cached is dropped, and a URL minted after a refusal is kept: a
    /// second refusal is not an expiry, and minting again would not fix it.
    private func refuse(_ url: URL, blobID: BlobID) -> Bool {
        guard let minted = cache[blobID], minted.url == url, !minted.afterRefusal else { return false }
        cache[blobID] = nil
        refusedBlobs.insert(blobID)
        logger.info("Chat photo URL refused", metadata: ["blobId": "\(blobID)"])
        return true
    }

    /// Queues `completion` on the one fetch of `blobID`'s URL, starting it if none is in flight.
    private func fetchURL(_ blobID: BlobID, completion: @escaping (URL?) -> Void) {
        let isFirst = waiters[blobID] == nil
        waiters[blobID, default: []].append(completion)
        guard isFirst else { return }
        Task {
            // Best-effort: the row keeps its BlurHash, and the next dequeue retries.
            let link = await mint(blobID)
            if let link {
                let minted = now()
                cache[blobID] = MintedURL(
                    url: link.url,
                    usableUntil: link.expiresAt.map {
                        max($0.addingTimeInterval(-Self.expiryMargin), minted.addingTimeInterval(Self.expiryMargin))
                    },
                    afterRefusal: refusedBlobs.remove(blobID) != nil
                )
            }
            let resolved = link?.url
            let completions = waiters.removeValue(forKey: blobID) ?? []
            for completion in completions { completion(resolved) }
        }
    }

    /// Mints `blobID`'s URL, logging how long the server took; nil when it has none or the call failed.
    private func mint(_ blobID: BlobID) async -> BlobDownloadLink? {
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let link = try await fetch(blobID)
            logger.info("Chat photo URL minted", metadata: [
                "blobId": "\(blobID)",
                "mintMs": "\(ChatMediaLoadReport.milliseconds(clock.now - start))",
                "outcome": "\(link == nil ? "none" : "ok")",
                "ttlSec": "\(link?.expiresAt.map { String(Int($0.timeIntervalSince(now()))) } ?? "none")",
            ])
            return link
        } catch {
            logger.warning("Chat photo URL mint failed", metadata: [
                "blobId": "\(blobID)",
                "mintMs": "\(ChatMediaLoadReport.milliseconds(clock.now - start))",
                "errorType": "\(type(of: error))",
                "errorCode": "\((error as NSError).code)",
            ])
            return nil
        }
    }

    /// Queues `completion` on the one fetch of the chat's decryption, starting it if none is in flight.
    private func awaitDecrypt(_ completion: @escaping (BlobDecrypt?) -> Void) {
        guard decryptWaiters == nil else {
            decryptWaiters?.append(completion)
            return
        }
        decryptWaiters = [completion]
        Task {
            // A chat whose key is not known yet leaves its photos on their BlurHash; the next
            // dequeue tries again.
            let resolved = await fetchDecrypt()
            if let resolved { decrypt = resolved }
            let completions = decryptWaiters ?? []
            decryptWaiters = nil
            for completion in completions { completion(resolved) }
        }
    }
}
