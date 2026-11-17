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

    public init(fetch: @escaping Fetch, decrypt: @escaping FetchDecrypt = { nil }, now: @escaping () -> Date = Date.init) {
        self.fetch = fetch
        self.fetchDecrypt = decrypt
        self.now = now
    }

    /// Where to draw `media` from, or nil for now.
    ///
    /// A BlurHash-only row returns nil without fetching. A photo already cached as `processor` draws
    /// it, or the full-size copy, from ``ChatMediaLocation/cached(sealed:)`` without fetching. A URL cache
    /// miss starts at most one fetch per blob and calls `onResolved` when it lands so the caller
    /// can redraw the row; a failed fetch leaves the row on its BlurHash, and the next call tries
    /// again. An encrypted photo also waits on the chat's decryption.
    public func location(
        for media: ChatMediaContent,
        canReact: Bool,
        cachedAs processor: ImageProcessor? = nil,
        onResolved: @escaping (ChatMediaLocation) -> Void
    ) -> ChatMediaLocation? {
        guard !ChatMediaCell.isBlurhashOnly(media, canReact: canReact),
              let blobID = media.blobID else { return nil }
        if let processor, ChatMediaImageSource.isCached(blobID: blobID, processor: processor) {
            return .cached(sealed: media.sealed != nil)
        }
        return resolve(blobID, sealed: media.sealed) { $0.map(onResolved) }
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
    private func resolve(_ blobID: BlobID, sealed: SealedBlob?, completion: @escaping (ChatMediaLocation?) -> Void) -> ChatMediaLocation? {
        if let url = usableURL(blobID) {
            guard let sealed else { return location(url: url, blobID: blobID, sealed: nil, decrypt: nil) }
            if let decrypt { return location(url: url, blobID: blobID, sealed: sealed, decrypt: decrypt) }
            awaitDecrypt { [weak self] decrypt in
                completion(decrypt.flatMap { self?.location(url: url, blobID: blobID, sealed: sealed, decrypt: $0) })
            }
            return nil
        }
        fetchURL(blobID) { [weak self] url in
            guard let self, let url else { return completion(nil) }
            guard let sealed else { return completion(location(url: url, blobID: blobID, sealed: nil, decrypt: nil)) }
            if let decrypt {
                return completion(location(url: url, blobID: blobID, sealed: sealed, decrypt: decrypt))
            }
            awaitDecrypt { [weak self] decrypt in
                completion(decrypt.flatMap { self?.location(url: url, blobID: blobID, sealed: sealed, decrypt: $0) })
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

    private func location(url: URL, blobID: BlobID, sealed: SealedBlob?, decrypt: BlobDecrypt?) -> ChatMediaLocation {
        var open: (@Sendable (Data) throws -> Data)?
        if let sealed, let decrypt {
            open = { try decrypt($0, blobID, sealed) }
        }
        return ChatMediaLocation(
            url: url,
            decrypt: open,
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
