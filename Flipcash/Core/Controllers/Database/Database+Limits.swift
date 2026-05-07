//
//  Database+Limits.swift
//  Flipcash
//
//  Created by Claude on 2025-02-09.
//

import Foundation
import FlipcashCore
import SQLite

nonisolated extension Database {

    // MARK: - Get -

    func getLimits() throws -> Limits? {
        let l = LimitsTable()

        let statement = try reader.prepareRowIterator("""
        SELECT
            l.data
        FROM
            limits l
        WHERE
            l.id = 1
        LIMIT 1;
        """)

        guard let row = try statement.map({ $0 }).first else {
            return nil
        }

        return try JSONDecoder().decode(Limits.self, from: row[l.data])
    }

    // MARK: - Insert -

    func insertLimits(_ limits: Limits) throws {
        let table = LimitsTable()
        let data = try JSONEncoder().encode(limits)

        try writer.run(
            table.table.upsert(
                table.id   <- 1,
                table.data <- data,

                onConflictOf: table.id
            )
        )
    }
}
