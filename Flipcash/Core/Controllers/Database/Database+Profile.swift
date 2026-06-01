//
//  Database+Profile.swift
//  Flipcash
//

import Foundation
import FlipcashCore
import SQLite

nonisolated extension Database {

    // MARK: - Get -

    func getProfile() throws -> Profile? {
        let t = ProfileTable()

        let statement = try reader.prepareRowIterator("""
        SELECT
            t.data
        FROM
            profile t
        WHERE
            t.id = 1
        LIMIT 1;
        """)

        guard let row = try statement.map({ $0 }).first else {
            return nil
        }

        return try JSONDecoder().decode(Profile.self, from: row[t.data])
    }

    func getUserFlags() throws -> UserFlags? {
        let t = UserFlagsTable()

        let statement = try reader.prepareRowIterator("""
        SELECT
            t.data
        FROM
            userFlags t
        WHERE
            t.id = 1
        LIMIT 1;
        """)

        guard let row = try statement.map({ $0 }).first else {
            return nil
        }

        return try JSONDecoder().decode(UserFlags.self, from: row[t.data])
    }

    // MARK: - Insert -

    func insertProfile(_ profile: Profile) throws {
        let table = ProfileTable()
        let data = try JSONEncoder().encode(profile)

        try writer.run(
            table.table.upsert(
                table.id   <- 1,
                table.data <- data,

                onConflictOf: table.id
            )
        )
    }

    func insertUserFlags(_ userFlags: UserFlags) throws {
        let table = UserFlagsTable()
        let data = try JSONEncoder().encode(userFlags)

        try writer.run(
            table.table.upsert(
                table.id   <- 1,
                table.data <- data,

                onConflictOf: table.id
            )
        )
    }
}
