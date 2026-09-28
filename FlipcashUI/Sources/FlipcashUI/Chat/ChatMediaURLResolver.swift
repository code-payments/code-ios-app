//
//  ChatMediaURLResolver.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// Resolves and caches the signed download URL for each photo in one conversation.
///
/// It is the only path from a photo row to the network, so a row that draws only its BlurHash — a
/// redacted photo, or any photo while the viewer previews a group they have not joined — never
/// fetches. Not fetching is what keeps that state from being a blur over bytes already on the device.
public final class ChatMediaURLResolver {

    /// Mints a download URL for a blob, or returns nil when the server has none to give.
    public typealias Fetch = @MainActor (BlobID) async throws -> URL?

    private let fetch: Fetch
    private var cache: [BlobID: URL] = [:]
    /// Everyone waiting on a blob's fetch, called with its URL, or nil when the fetch failed.
    private var waiters: [BlobID: [(URL?) -> Void]] = [:]

    public init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    /// The URL to draw `media` from, or nil for now.
    ///
    /// A BlurHash-only row returns nil without fetching. A cache miss starts at most one fetch per
    /// blob and calls `onResolved` when it lands so the caller can redraw the row; a failed fetch
    /// leaves the row on its BlurHash, and the next call tries again.
    public func url(
        for media: ChatMediaContent,
        canReact: Bool,
        onResolved: @escaping (URL) -> Void
    ) -> URL? {
        guard !ChatMediaCell.isBlurhashOnly(media, canReact: canReact),
              let blobID = media.blobID else { return nil }
        return resolve(blobID) { $0.map(onResolved) }
    }

    /// The URL to draw a quoted photo's thumbnail from, or nil for now, sharing the photo row's cache.
    ///
    /// Nil without fetching for anything but a photo whose bytes the viewer may see: a quote of text,
    /// cash, or an unavailable original, a redacted photo (``ChatQuote/Kind/media(thumbnailBlobID:)``
    /// carries no blob), or any quote while the viewer previews a group they have not joined.
    public func thumbnailURL(
        for kind: ChatQuote.Kind,
        canReact: Bool,
        onResolved: @escaping (URL) -> Void
    ) -> URL? {
        guard let blobID = Self.thumbnailBlobID(for: kind, canReact: canReact) else { return nil }
        return resolve(blobID) { $0.map(onResolved) }
    }

    /// The URL to draw a quoted photo's thumbnail from, waiting for the fetch; nil when there is none
    /// to draw or the fetch failed. Follows the same rules as the callback form.
    public func thumbnailURL(for kind: ChatQuote.Kind, canReact: Bool) async -> URL? {
        guard let blobID = Self.thumbnailBlobID(for: kind, canReact: canReact) else { return nil }
        return await withCheckedContinuation { continuation in
            var resumed = false
            let immediate = resolve(blobID) { url in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: url)
            }
            if let immediate, !resumed {
                resumed = true
                continuation.resume(returning: immediate)
            }
        }
    }

    private static func thumbnailBlobID(for kind: ChatQuote.Kind, canReact: Bool) -> BlobID? {
        switch kind {
        case .media(let thumbnailBlobID):
            canReact ? thumbnailBlobID : nil
        case .text, .cash, .unavailable:
            nil
        }
    }

    /// The cached URL for `blobID`, or nil after queueing `completion` on the one fetch for it.
    private func resolve(_ blobID: BlobID, completion: @escaping (URL?) -> Void) -> URL? {
        if let cached = cache[blobID] { return cached }
        let isFirst = waiters[blobID] == nil
        waiters[blobID, default: []].append(completion)
        guard isFirst else { return nil }
        Task {
            // Best-effort: the row keeps its BlurHash, and the next dequeue retries.
            let resolved = try? await fetch(blobID)
            if let resolved { cache[blobID] = resolved }
            let completions = waiters.removeValue(forKey: blobID) ?? []
            for completion in completions { completion(resolved) }
        }
        return nil
    }
}
