//
//  ProfileAvatarStore.swift
//  Flipcash
//

import Foundation
import FlipcashCore

private let logger = Logger(label: "flipcash.profile-avatars")

/// Other users' profile-picture thumbnails, as raw bytes so every surface renders them through the
/// same `ContactAvatarView(imageData:)` path address-book avatars use.
///
/// Backed by ``ProfilePictureCache``, so bytes fetched in one launch are on screen at first paint in
/// the next. The in-memory map is what `@Observable` watches — the disk cache alone cannot invalidate
/// a view — and it is populated from disk without a round trip.
@Observable
final class ProfileAvatarStore {

    private var dataByUser: [UserID: Data] = [:]

    /// Which blob each cached entry came from. A user who changes their picture keeps their user id
    /// and gets a new blob id, so this is what tells a stale entry from a current one.
    @ObservationIgnored private var blobByUser: [UserID: BlobID] = [:]

    @ObservationIgnored private var inFlight: Set<UserID> = []
    @ObservationIgnored private let cache: ProfilePictureCache
    @ObservationIgnored private let mintURL: (BlobID, UserID) async throws -> URL?
    @ObservationIgnored private let fetch: (URL) async throws -> Data

    /// - Parameters:
    ///   - mintURL: mints a download URL for a blob. Injected because `FlipClient` is a concrete
    ///     class with a live gRPC channel, so there is no fake to pass a test.
    ///   - fetch: downloads the bytes at a URL.
    init(
        cache: ProfilePictureCache = .shared,
        mintURL: @escaping (BlobID, UserID) async throws -> URL?,
        fetch: @escaping (URL) async throws -> Data = { url in
            try await URLSession.shared.data(from: url).0
        }
    ) {
        self.cache   = cache
        self.mintURL = mintURL
        self.fetch   = fetch
    }

    convenience init(flipClient: FlipClient, owner: KeyPair, cache: ProfilePictureCache = .shared) {
        self.init(
            cache: cache,
            mintURL: { blobID, userID in
                try await flipClient.blobDownloadURL(
                    blobID: blobID,
                    owner: owner,
                    accessContext: .profile(userID)
                )
            }
        )
    }

    /// The cached thumbnail bytes for a user, or nil until ``load(userID:picture:)`` has them.
    func data(for userID: UserID?) -> Data? {
        userID.flatMap { dataByUser[$0] }
    }

    /// Makes a member's current thumbnail available to ``data(for:)``.
    ///
    /// Returns without a round trip when the bytes are already in memory or on disk for that exact
    /// blob. Download URLs expire, so one is minted per fetch and never stored.
    func load(userID: UserID?, picture: ProfilePicture?) async {
        guard let userID, let blobID = picture?.thumbnailBlobID else { return }

        // A different blob under the same user id is a changed picture, not a cache hit.
        if blobByUser[userID] == blobID, dataByUser[userID] != nil { return }
        guard !inFlight.contains(userID) else { return }

        if let cached = cache.data(for: blobID) {
            store(cached, userID: userID, blobID: blobID)
            return
        }

        inFlight.insert(userID)
        defer { inFlight.remove(userID) }

        do {
            guard let url = try await mintURL(blobID, userID) else { return }

            let data = try await fetch(url)
            cache.write(data, for: blobID)
            store(data, userID: userID, blobID: blobID)
        } catch {
            guard !Task.isCancelled else { return }
            // The surfaces render the monogram placeholder without it.
            logger.info("Failed to load a profile avatar", metadata: [
                "userId": "\(userID)",
                "error": "\(error)",
            ])
        }
    }

    /// Warms several members' thumbnails at once, for a list that is about to draw all of them —
    /// including the rows below the fold, so scrolling never lands on a blurhash.
    ///
    /// Returns immediately. Each fetch lands in the store on its own and invalidates only the rows
    /// that read it; a caller that awaited the set would hold the whole list behind the slowest one.
    func preload(_ members: [(userID: UserID?, picture: ProfilePicture?)]) {
        for member in members {
            Task { await load(userID: member.userID, picture: member.picture) }
        }
    }

    private func store(_ data: Data, userID: UserID, blobID: BlobID) {
        dataByUser[userID] = data
        blobByUser[userID] = blobID
    }
}
