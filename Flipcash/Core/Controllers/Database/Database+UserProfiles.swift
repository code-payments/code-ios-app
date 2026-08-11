//
//  Database+UserProfiles.swift
//  Flipcash
//

import Foundation
import FlipcashCore
import SQLite

/// Keyed cache of other users' `Profile`s. The signed-in user's own profile
/// lives in the singleton `profile` table (`Database+Profile.swift`); this table
/// holds counterpart/tip-recipient/blocked-user profiles keyed by user id.
nonisolated extension Database {

    // MARK: - Get -

    /// The cached profile for `userID`, or `nil` when it hasn't been fetched yet.
    func getUserProfile(userID: UserID) throws -> Profile? {
        let t = UserProfileTable()
        guard let row = try reader.pluck(t.table.filter(t.userID == userID)) else {
            return nil
        }
        return try JSONDecoder().decode(Profile.self, from: row[t.data])
    }

    // MARK: - Insert -

    /// Cache `profile` under `userID`, replacing any existing row.
    func upsertUserProfile(_ profile: Profile, userID: UserID) throws {
        let t = UserProfileTable()
        let data = try JSONEncoder().encode(profile)
        try writer.run(t.table.upsert(
            t.userID <- userID,
            t.data   <- data,
            onConflictOf: t.userID
        ))
    }

    // MARK: - Delete -

    /// Remove the cached profile for `userID`.
    func deleteUserProfile(userID: UserID) throws {
        let t = UserProfileTable()
        try writer.run(t.table.filter(t.userID == userID).delete())
    }
}
