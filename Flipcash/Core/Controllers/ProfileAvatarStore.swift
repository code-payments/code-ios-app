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
/// Backed by ``BlobCache``, so bytes fetched in one launch are on screen at first paint in
/// the next. The in-memory map is what `@Observable` watches — the disk cache alone cannot invalidate
/// a view — and it is populated from disk without a round trip.
@Observable
final class ProfileAvatarStore {

    /// Whose picture an entry is. A group chat's picture is a blob like any member's, and reaches
    /// the client the same way — only the access context the download URL is minted through
    /// differs, which is what this selects.
    enum AvatarSubject: Hashable, Sendable {
        case user(UserID)
        case chat(ConversationID)

        /// The context this subject's blobs authorize through.
        var accessContext: BlobAccessContext {
            switch self {
            case .user(let userID):           .userProfile(userID)
            case .chat(let conversationID):   .chatProfile(conversationID)
            }
        }
    }

    private var dataBySubject: [AvatarSubject: Data] = [:]

    /// Which blob each cached entry came from. A subject that changes its picture keeps its id and
    /// gets a new blob id, so this is what tells a stale entry from a current one.
    @ObservationIgnored private var blobBySubject: [AvatarSubject: BlobID] = [:]

    /// The fetch currently running for a subject, for later callers to join. A caller that was
    /// merely turned away could not learn that the fetch it skipped had failed, and nothing retried.
    @ObservationIgnored private var inFlight: [AvatarSubject: Task<Void, Never>] = [:]
    @ObservationIgnored private let cache: BlobCache
    @ObservationIgnored private let mintURL: (BlobID, AvatarSubject) async throws -> URL?
    @ObservationIgnored private let fetch: (URL) async throws -> Data

    /// - Parameters:
    ///   - mintURL: mints a download URL for a blob. Injected because `FlipClient` is a concrete
    ///     class with a live gRPC channel, so there is no fake to pass a test.
    ///   - fetch: downloads the bytes at a URL.
    init(
        cache: BlobCache = .profilePictures,
        mintURL: @escaping (BlobID, AvatarSubject) async throws -> URL?,
        fetch: @escaping (URL) async throws -> Data = { url in
            try await URLSession.shared.data(from: url).0
        }
    ) {
        self.cache   = cache
        self.mintURL = mintURL
        self.fetch   = fetch
    }

    convenience init(flipClient: FlipClient, owner: KeyPair, cache: BlobCache = .profilePictures) {
        self.init(
            cache: cache,
            mintURL: { blobID, subject in
                try await flipClient.blobDownloadURL(
                    blobID: blobID,
                    owner: owner,
                    accessContext: subject.accessContext
                )
            }
        )
    }

    /// The cached thumbnail bytes for a user, or nil until ``load(userID:picture:)`` has them.
    func data(for userID: UserID?) -> Data? {
        userID.flatMap { data(for: .user($0)) }
    }

    /// The cached thumbnail bytes for any subject, or nil until ``load(_:picture:)`` has them.
    func data(for subject: AvatarSubject?) -> Data? {
        subject.flatMap { dataBySubject[$0] }
    }

    /// Makes a member's current thumbnail available to ``data(for:)``.
    func load(userID: UserID?, picture: ProfilePicture?) async {
        guard let userID else { return }
        await load(.user(userID), picture: picture)
    }

    /// Makes a subject's current thumbnail available to ``data(for:)``.
    ///
    /// Returns without a round trip when the bytes are already in memory or on disk for that exact
    /// blob, and joins the fetch already running for that subject rather than starting a second one.
    func load(_ subject: AvatarSubject, picture: ProfilePicture?) async {
        guard let blobID = picture?.thumbnailBlobID else { return }

        // A different blob under the same id is a changed picture, not a cache hit.
        if blobBySubject[subject] == blobID, dataBySubject[subject] != nil { return }

        if let cached = cache.data(for: blobID) {
            store(cached, subject: subject, blobID: blobID)
            return
        }

        if let running = inFlight[subject] {
            await running.value
            return
        }

        // Unstructured, so the fetch outlives the caller that happened to start it. Callers are
        // SwiftUI `.task`s, cancelled when their view is covered or their id changes; a fetch
        // cancelled with them stored nothing, and the surface kept its blurhash for good.
        let task = Task { [self] in
            await download(blobID: blobID, subject: subject)
            inFlight[subject] = nil
        }
        inFlight[subject] = task
        await task.value
    }

    /// Download URLs expire, so one is minted per fetch and never stored.
    private func download(blobID: BlobID, subject: AvatarSubject) async {
        do {
            guard let url = try await mintURL(blobID, subject) else { return }

            let data = try await fetch(url)
            cache.write(data, for: blobID)
            store(data, subject: subject, blobID: blobID)
        } catch {
            guard !Task.isCancelled else { return }
            // The surfaces render the monogram placeholder without it.
            logger.info("Failed to load a profile avatar", metadata: [
                "subject": "\(subject)",
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

    /// Warms several subjects' thumbnails at once. See ``preload(_:)``.
    func preload(_ subjects: [(subject: AvatarSubject, picture: ProfilePicture?)]) {
        for subject in subjects {
            Task { await load(subject.subject, picture: subject.picture) }
        }
    }

    private func store(_ data: Data, subject: AvatarSubject, blobID: BlobID) {
        dataBySubject[subject] = data
        blobBySubject[subject] = blobID
    }
}
