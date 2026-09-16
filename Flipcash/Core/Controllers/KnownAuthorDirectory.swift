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

/// Locally-cached identities for chat senders whose own chat cannot name them.
///
/// A large group embeds only a subset of its roster — `chat.v1.Metadata.members` documents it as
/// one — and the contract carries no roster RPC, so a sender outside that subset arrives as a bare
/// user id and their rows would draw unattributed. This answers from what the device already holds:
/// every chat roster row in the store, and every profile it has fetched. Nothing here goes to the
/// network, so a sender this client has never encountered stays unnamed.
@MainActor
@Observable
final class KnownAuthorDirectory {

    /// The loaded table. Replaced wholesale, and only when its contents actually changed.
    private(set) var snapshot: Snapshot = .empty

    /// Reads the local cache. Injected because `Database` opens a real SQLite connection, so there
    /// is no fake to hand a test.
    @ObservationIgnored private let read: @Sendable () throws -> [UserID: ConversationMember]

    /// The reload in flight, so concurrent requests collapse onto one read of the same store.
    @ObservationIgnored private var reloadTask: Task<Void, Never>?

    init(read: @escaping @Sendable () throws -> [UserID: ConversationMember]) {
        self.read = read
    }

    convenience init(database: Database) {
        self.init(read: { try database.knownMembers() })
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
