//
//  Database+Profile.swift
//  Flipcash
//

import Foundation
import FlipcashCore
import SQLite

nonisolated extension Database {

    // MARK: - Get -

    /// The profile stored in the database file at `url`, or `nil` when there is no readable
    /// store or no decodable profile in it.
    ///
    /// Reads through a read-only connection only, so another owner's store can be inspected
    /// without creating tables, migrating it, or deleting it for a stale schema version.
    public static func storedProfile(at url: URL) -> Profile? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let table = ProfileTable()
        do {
            let connection = try Connection(url.path, readonly: true)
            connection.busyTimeout = 2

            let query = table.table.select(table.data).filter(table.id == 1)
            guard let row = try connection.pluck(query) else {
                return nil
            }

            return try JSONDecoder().decode(Profile.self, from: row[table.data])
        } catch {
            // Best effort: an unreadable store leaves the row on its cached title.
            return nil
        }
    }

    public func getProfile() throws -> Profile? {
        try getSingleton(Profile.self, in: ProfileTable())
    }

    public func getUserFlags() throws -> UserFlags? {
        try getSingleton(UserFlags.self, in: UserFlagsTable())
    }

    // MARK: - Insert -

    public func insertProfile(_ profile: Profile) throws {
        try upsertSingleton(profile, in: ProfileTable())
    }

    public func insertUserFlags(_ userFlags: UserFlags) throws {
        try upsertSingleton(userFlags, in: UserFlagsTable())
    }
}
