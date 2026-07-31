//
//  BlocklistController.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

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
    func refresh() async {
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
    let flipClient: FlipClient
    let owner: KeyPair

    func getBlockedUserProfiles() async throws -> [BlockedUserProfile] {
        let blocked = try await flipClient.getBlocklist(owner: owner)
        var profiles: [BlockedUserProfile] = []
        for user in blocked {
            let profile = try? await flipClient.fetchProfile(userID: user.userID, owner: owner)
            let name = profile?.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? ConversationController.fallbackCounterpartName
            profiles.append(BlockedUserProfile(
                userID: user.userID,
                blockedAt: user.blockedAt,
                displayName: name,
                avatarBlurhash: profile?.profilePicture?.thumbnailBlurhash
            ))
        }
        return profiles
    }

    func block(userID: UserID) async throws { try await flipClient.blockUser(userID: userID, owner: owner) }
    func unblock(userID: UserID) async throws { try await flipClient.unblockUser(userID: userID, owner: owner) }
}
