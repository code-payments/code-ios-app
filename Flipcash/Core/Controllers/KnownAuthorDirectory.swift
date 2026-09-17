//
//  KnownAuthorDirectory.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore
import FlipcashStore

nonisolated private let logger = Logger(label: "flipcash.known-authors")

/// Identities for chat senders whose own chat cannot name them.
///
/// A large group embeds only a subset of its roster — `chat.v1.Metadata.members` documents it as
/// one — and the contract carries no roster RPC, so a sender outside that subset arrives as a bare
/// user id and their rows would draw unattributed. ``reload()`` answers from what the device already
/// holds: every chat roster row in the store, and every profile it has fetched. ``resolve(_:)``
/// covers the rest by user id through `Profile.GetProfile`, which is public for any user, and caches
/// what it gets so the next launch names that sender without a round trip.
@MainActor
@Observable
final class KnownAuthorDirectory {

    /// The loaded table. Replaced wholesale, and only when its contents actually changed.
    private(set) var snapshot: Snapshot = .empty

    /// Reads the local cache. Injected because `Database` opens a real SQLite connection, so there
    /// is no fake to hand a test.
    @ObservationIgnored private let read: @Sendable () throws -> [UserID: ConversationMember]

    /// Fetches one user's public profile. Injected for the same reason `read` is — `FlipClient`
    /// holds a live gRPC channel.
    @ObservationIgnored private let fetch: (UserID) async throws -> Profile

    /// Writes a fetched profile into the local cache, which is what ``reload()`` then reads it back
    /// out of — the fetch and the table stay one source rather than two.
    @ObservationIgnored private let cache: @Sendable (Profile, UserID) throws -> Void

    /// Senders already asked about, so a transcript that re-maps mid-fetch does not ask again and a
    /// user the server has no name for is asked once rather than on every tick. A failed request is
    /// removed again, so reopening the chat retries it.
    @ObservationIgnored private var requested: Set<UserID> = []

    /// The reload in flight, so concurrent requests collapse onto one read of the same store.
    @ObservationIgnored private var reloadTask: Task<Void, Never>?

    init(
        read: @escaping @Sendable () throws -> [UserID: ConversationMember],
        fetch: @escaping (UserID) async throws -> Profile,
        cache: @escaping @Sendable (Profile, UserID) throws -> Void
    ) {
        self.read = read
        self.fetch = fetch
        self.cache = cache
    }

    convenience init(database: Database, flipClient: FlipClient, owner: KeyPair) {
        self.init(
            read: { try database.knownMembers() },
            fetch: { try await flipClient.fetchProfile(userID: $0, owner: owner) },
            cache: { try database.upsertUserProfile($0, userID: $1) }
        )
    }

    /// Re-reads the local cache off the main thread, landing a new ``snapshot`` only if the table
    /// changed. Safe to call whenever a roster might have moved; a repeat while one is running is
    /// dropped rather than queued.
    func reload() async {
        if let reloadTask {
            await reloadTask.value
            return
        }
        let task = Task { [read] in
            let members = await Task.detached {
                do {
                    return try read()
                } catch {
                    // The transcript falls back to the chat's own roster without it.
                    logger.info("Failed to read known chat authors", metadata: ["error": "\(error)"])
                    return [UserID: ConversationMember]()
                }
            }.value
            guard members != snapshot.membersByUserID else { return }
            snapshot = Snapshot(membersByUserID: members)
        }
        reloadTask = task
        await task.value
        reloadTask = nil
    }

    /// Names the senders ``reload()`` could not, by fetching their profiles and caching them.
    ///
    /// One request per sender per launch: a chat roster is the cheaper source and wins, so only the
    /// ids it leaves out cost a round trip, and an id that comes back nameless is not asked again.
    /// The requests run in sequence — a window rarely holds more than a handful of unnamed senders,
    /// and a burst of them at open would contend with the messages the screen is still loading.
    func resolve(_ userIDs: some Sequence<UserID>) async {
        var missing: [UserID] = []
        for userID in userIDs where snapshot.membersByUserID[userID] == nil {
            guard requested.insert(userID).inserted else { continue }
            missing.append(userID)
        }
        guard !missing.isEmpty else { return }

        var fetched: [(userID: UserID, profile: Profile)] = []
        for userID in missing {
            do {
                let profile = try await fetch(userID)
                // A user the server has no profile for comes back empty. There is nothing to name
                // their rows with, and caching it would hold a blank line above every one of them.
                guard profile.displayName?.isEmpty == false else { continue }
                fetched.append((userID, profile))
            } catch {
                // Their rows stay unattributed, and the next open asks again.
                requested.remove(userID)
                logger.info("Failed to fetch a chat author's profile", metadata: [
                    "userID": "\(userID)",
                    "error": "\(error)",
                ])
            }
        }
        guard !fetched.isEmpty else { return }

        let landed = fetched
        await Task.detached { [cache] in
            for entry in landed {
                do {
                    try cache(entry.profile, entry.userID)
                } catch {
                    logger.info("Failed to cache a chat author's profile", metadata: ["error": "\(error)"])
                }
            }
        }.value

        await reload()
    }

    /// An immutable identity table, compared by identity rather than by contents.
    ///
    /// It is replaced wholesale and only when the underlying rows changed, so two snapshots hold
    /// the same table exactly when they are the same object. That is what makes it cheap enough to
    /// carry in `ConversationLoadCoordinator.Inputs`, which is compared on every observation tick.
    nonisolated final class Snapshot: Equatable, Sendable {

        static let empty = Snapshot(membersByUserID: [:])

        let membersByUserID: [UserID: ConversationMember]

        init(membersByUserID: [UserID: ConversationMember]) {
            self.membersByUserID = membersByUserID
        }

        static func == (lhs: Snapshot, rhs: Snapshot) -> Bool { lhs === rhs }
    }
}
