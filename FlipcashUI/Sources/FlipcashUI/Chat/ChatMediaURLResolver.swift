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
    /// Decrypts an end-to-end encrypted blob into its image bytes, throwing when it fails to
    /// authenticate or is not the declared length.
    public typealias BlobDecrypt = @Sendable (Data, BlobID, SealedBlob) throws -> Data
    /// Builds the conversation's blob decryption, or returns nil while it can't be (its key is not
    /// known yet).
    public typealias FetchDecrypt = @MainActor () async -> BlobDecrypt?

    private let fetch: Fetch
    private let fetchDecrypt: FetchDecrypt
    private var cache: [BlobID: URL] = [:]
    /// Everyone waiting on a blob's fetch, called with its URL, or nil when the fetch failed.
    private var waiters: [BlobID: [(URL?) -> Void]] = [:]
    private var decrypt: BlobDecrypt?
    /// Everyone waiting on the decryption, or nil when no fetch of it is in flight.
    private var decryptWaiters: [(BlobDecrypt?) -> Void]?

    public init(fetch: @escaping Fetch, decrypt: @escaping FetchDecrypt = { nil }) {
        self.fetch = fetch
        self.fetchDecrypt = decrypt
    }

    /// Where to draw `media` from, or nil for now.
    ///
    /// A BlurHash-only row returns nil without fetching. A cache miss starts at most one fetch per
    /// blob and calls `onResolved` when it lands so the caller can redraw the row; a failed fetch
    /// leaves the row on its BlurHash, and the next call tries again. An encrypted photo also waits
    /// on the chat's decryption.
    public func location(
        for media: ChatMediaContent,
        canReact: Bool,
        onResolved: @escaping (ChatMediaLocation) -> Void
    ) -> ChatMediaLocation? {
        guard !ChatMediaCell.isBlurhashOnly(media, canReact: canReact),
              let blobID = media.blobID else { return nil }
        return resolve(blobID, sealed: media.sealed) { $0.map(onResolved) }
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
        return await withCheckedContinuation { continuation in
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
        if let url = cache[blobID] {
            guard let sealed else { return ChatMediaLocation(url: url) }
            if let decrypt { return Self.location(url: url, blobID: blobID, sealed: sealed, decrypt: decrypt) }
            awaitDecrypt { decrypt in
                completion(decrypt.map { Self.location(url: url, blobID: blobID, sealed: sealed, decrypt: $0) })
            }
            return nil
        }
        fetchURL(blobID) { [weak self] url in
            guard let url else { return completion(nil) }
            guard let sealed else { return completion(ChatMediaLocation(url: url)) }
            if let decrypt = self?.decrypt {
                return completion(Self.location(url: url, blobID: blobID, sealed: sealed, decrypt: decrypt))
            }
            self?.awaitDecrypt { decrypt in
                completion(decrypt.map { Self.location(url: url, blobID: blobID, sealed: sealed, decrypt: $0) })
            }
        }
        return nil
    }

    private static func location(url: URL, blobID: BlobID, sealed: SealedBlob, decrypt: @escaping BlobDecrypt) -> ChatMediaLocation {
        ChatMediaLocation(url: url) { try decrypt($0, blobID, sealed) }
    }

    /// Queues `completion` on the one fetch of `blobID`'s URL, starting it if none is in flight.
    private func fetchURL(_ blobID: BlobID, completion: @escaping (URL?) -> Void) {
        let isFirst = waiters[blobID] == nil
        waiters[blobID, default: []].append(completion)
        guard isFirst else { return }
        Task {
            // Best-effort: the row keeps its BlurHash, and the next dequeue retries.
            let resolved = try? await fetch(blobID)
            if let resolved { cache[blobID] = resolved }
            let completions = waiters.removeValue(forKey: blobID) ?? []
            for completion in completions { completion(resolved) }
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
