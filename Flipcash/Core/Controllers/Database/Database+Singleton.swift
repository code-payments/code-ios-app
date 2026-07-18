//
//  Database+Singleton.swift
//  Flipcash
//

import Foundation
import FlipcashCore
import SQLite

/// A table holding exactly one JSON-encoded row, keyed `id = 1`.
nonisolated protocol SingletonTable {
    static var name: String { get }
    var table: Table { get }
    var id: Expression<Int> { get }
    var data: Expression<Data> { get }
}

extension ProfileTable: SingletonTable {}
extension UserFlagsTable: SingletonTable {}
extension LimitsTable: SingletonTable {}

nonisolated extension Database {

    /// Returns the singleton row decoded as `T`, or `nil` when the table is empty.
    func getSingleton<T: Decodable, S: SingletonTable>(_ type: T.Type, in table: S) throws -> T? {
        let statement = try reader.prepareRowIterator("""
        SELECT
            t.data
        FROM
            \(S.name) t
        WHERE
            t.id = 1
        LIMIT 1;
        """)

        guard let row = try statement.map({ $0 }).first else {
            return nil
        }

        return try JSONDecoder().decode(T.self, from: row[table.data])
    }

    /// Encodes `value` and writes it as the singleton row, replacing any existing one.
    func upsertSingleton<T: Encodable, S: SingletonTable>(_ value: T, in table: S) throws {
        let data = try JSONEncoder().encode(value)

        try writer.run(
            table.table.upsert(
                table.id   <- 1,
                table.data <- data,

                onConflictOf: table.id
            )
        )
    }
}
