//
//  Database+Blocklist.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore
import SQLite

nonisolated extension Database {

    /// The cached blocklist, most-recently-blocked first.
    func getBlockedUsers() throws -> [BlockedUserProfile] {
        let b = BlocklistTable()
        let rows = try reader.prepareRowIterator(b.table.order(b.blockedAt.desc))
        return try rows.map { row in
            BlockedUserProfile(
                userID: row[b.userID],
                blockedAt: Date(timeIntervalSinceReferenceDate: row[b.blockedAt]),
                displayName: row[b.displayName],
                avatarBlurhash: row[b.avatarBlurhash]
            )
        }
    }

    /// Atomically replace the entire cached blocklist with `users`.
    func replaceBlocklist(_ users: [BlockedUserProfile]) throws {
        let b = BlocklistTable()
        try writer.transaction {
            try writer.run(b.table.delete())
            for user in users {
                try writer.run(b.table.insert(
                    b.userID         <- user.userID,
                    b.blockedAt      <- user.blockedAt.timeIntervalSinceReferenceDate,
                    b.displayName    <- user.displayName,
                    b.avatarBlurhash <- user.avatarBlurhash
                ))
            }
        }
    }

    /// Insert or replace one blocked user (optimistic block).
    func upsertBlockedUser(_ user: BlockedUserProfile) throws {
        let b = BlocklistTable()
        try writer.run(b.table.upsert(
            b.userID         <- user.userID,
            b.blockedAt      <- user.blockedAt.timeIntervalSinceReferenceDate,
            b.displayName    <- user.displayName,
            b.avatarBlurhash <- user.avatarBlurhash,
            onConflictOf: b.userID
        ))
    }

    /// Remove one blocked user (optimistic unblock).
    func deleteBlockedUser(userID: UserID) throws {
        let b = BlocklistTable()
        try writer.run(b.table.filter(b.userID == userID).delete())
    }
}
