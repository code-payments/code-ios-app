//
//  BlocklistController.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore
import FlipcashStore

nonisolated private let logger = Logger(label: "flipcash.blocklist-controller")

/// The backend the controller talks to — abstracted so tests inject a fake.
@MainActor
protocol BlocklistFetching: Sendable {
    func getBlockedUserProfiles() async throws -> [BlockedUserProfile]
    func block(userID: UserID) async throws
    func unblock(userID: UserID) async throws
}

/// Owns the user's blocklist: an in-memory list backing the Blocked screen and a
/// persistent cache, refreshed from the server on foreground. Exposes `isBlocked`
/// and optimistic `block`/`unblock`.
@MainActor
@Observable
final class BlocklistController {

    /// Blocked users, most-recently-blocked first.
    private(set) var blockedUsers: [BlockedUserProfile] = []

    @ObservationIgnored private let fetching: any BlocklistFetching
    @ObservationIgnored private let database: Database

    /// Invoked after any change to the blocklist so the conversation feed can
    /// reconcile which chats are hidden.
    @ObservationIgnored var onBlocklistChanged: () -> Void = {}

    /// The pass currently in flight, so concurrent callers share one instead of each
    /// opening its own.
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init(fetching: any BlocklistFetching, database: Database) {
        self.fetching = fetching
        self.database = database
        blockedUsers = (try? database.getBlockedUsers()) ?? []
    }

    /// Returns whether `userID` is currently in the blocklist.
    func isBlocked(_ userID: UserID) -> Bool {
        blockedUsers.contains { $0.userID == userID }
    }

    /// Pull the authoritative blocklist, resolve display profiles, and atomically
    /// replace both memory and the cache. Best-effort — keeps the cached list on failure.
    ///
    /// A caller arriving while a pass is in flight joins it rather than starting a second.
    /// Bootstrap and the foreground transition both refresh, and on a cold launch they land
    /// close enough together that two passes duplicate every profile round trip the list costs.
    func refresh() async {
        if let refreshTask {
            return await refreshTask.value
        }
        let task = Task { await self.performRefresh() }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func performRefresh() async {
        do {
            let users = try await fetching.getBlockedUserProfiles()
            blockedUsers = users
            onBlocklistChanged()
            try database.replaceBlocklist(users)
        } catch {
            logger.error("Failed to refresh blocklist", metadata: ["error": "\(error)"])
            ErrorReporting.captureError(error, reason: "Failed to refresh blocklist")
        }
    }

    /// Block a user, then optimistically add them so the list + `isBlocked` update
    /// without waiting for a refresh.
    func block(userID: UserID, displayName: String, avatarBlurhash: String?) async throws {
        try await fetching.block(userID: userID)
        // Note: Date() is an approximate local timestamp; it is corrected to the server's blockedAt on the next refresh(), which replaces the whole list.
        let entry = BlockedUserProfile(userID: userID, blockedAt: Date(), displayName: displayName, avatarBlurhash: avatarBlurhash)
        if !isBlocked(userID) {
            blockedUsers.insert(entry, at: 0)
        }
        try? database.upsertBlockedUser(entry)
        onBlocklistChanged()
    }

    /// Unblock a user, then optimistically remove them.
    func unblock(userID: UserID) async throws {
        try await fetching.unblock(userID: userID)
        blockedUsers.removeAll { $0.userID == userID }
        try? database.deleteBlockedUser(userID: userID)
        onBlocklistChanged()
    }
}

// MARK: - Production backend

/// Resolves the server blocklist (userID + blockedAt) into display profiles by
/// fetching each user's profile, and forwards block/unblock to `FlipClient`.
@MainActor
struct FlipBlocklisting: BlocklistFetching {

    /// How many blocked profiles resolve at once. The list costs one profile round trip
    /// per entry and the whole set is wanted at launch, alongside the balance, rates and
    /// history syncs it shares that moment with — so it drains at a bounded width rather
    /// than opening every request together. Matches `ConversationController`'s backfill.
    static let resolveConcurrency = 4

    let flipClient: FlipClient
    let owner: KeyPair

    func getBlockedUserProfiles() async throws -> [BlockedUserProfile] {
        let blocked = try await flipClient.getBlocklist(owner: owner)
        return await Self.resolve(blocked) { [flipClient, owner] userID in
            try await flipClient.fetchProfile(userID: userID, owner: owner)
        }
    }

    /// Resolves blocked entries to the display profiles the Blocked list shows, in the
    /// order the server returned them.
    ///
    /// A failed profile leaves the entry in place under the fallback name — a blocked
    /// user must stay blocked and visible even when their profile can't be read.
    static func resolve(
        _ blocked: [BlockedUserEntry],
        concurrency: Int = resolveConcurrency,
        fetch: @escaping @Sendable (UserID) async throws -> Profile
    ) async -> [BlockedUserProfile] {
        guard !blocked.isEmpty else { return [] }

        // Collected by index and read back in input order: the server returns the list
        // most-recently-blocked first and the screen shows it that way, so the order the
        // profiles happen to come back in must not reorder it.
        var resolved = [Profile?](repeating: nil, count: blocked.count)
        await withTaskGroup(of: (index: Int, profile: Profile?).self) { group in
            var next = 0
            func addTask(at index: Int) {
                let userID = blocked[index].userID
                group.addTask { (index, try? await fetch(userID)) }
            }
            // Start a window, then replace each task as it finishes, so the list drains at
            // a steady width instead of in lock-stepped batches.
            while next < min(concurrency, blocked.count) {
                addTask(at: next)
                next += 1
            }
            while let result = await group.next() {
                resolved[result.index] = result.profile
                guard next < blocked.count else { continue }
                addTask(at: next)
                next += 1
            }
        }
        return blocked.indices.map { displayProfile(for: blocked[$0], profile: resolved[$0]) }
    }

    private static func displayProfile(for entry: BlockedUserEntry, profile: Profile?) -> BlockedUserProfile {
        BlockedUserProfile(
            userID: entry.userID,
            blockedAt: entry.blockedAt,
            displayName: profile?.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? ConversationController.fallbackCounterpartName,
            avatarBlurhash: profile?.profilePicture?.thumbnailBlurhash
        )
    }

    func block(userID: UserID) async throws { try await flipClient.blockUser(userID: userID, owner: owner) }
    func unblock(userID: UserID) async throws { try await flipClient.unblockUser(userID: userID, owner: owner) }
}
