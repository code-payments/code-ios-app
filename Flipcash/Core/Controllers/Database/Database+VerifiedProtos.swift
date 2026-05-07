//
//  Database+VerifiedProtos.swift
//  Flipcash
//

import Foundation
import FlipcashCore
import SQLite

nonisolated extension Database: VerifiedProtoStore {

    // MARK: - Verified Rates -

    /// Stream ticks deliver ~200 currencies at a time; wrap the upserts in one
    /// transaction so we commit once per tick instead of once per row.
    /// `silent: true` because the `verified_rate` table has no UI listeners —
    /// the service's `ratesPublisher` already drives downstream updates.
    public func writeRates(_ rows: [StoredRateRow]) throws {
        guard !rows.isEmpty else { return }
        let table = VerifiedRateTable()
        try transaction(silent: true) { _ in
            for row in rows {
                try writer.run(
                    table.table.upsert(
                        table.currency <- row.currency,
                        table.rateProto <- row.rateProto,
                        onConflictOf: table.currency
                    )
                )
            }
        }
    }

    public func allRates() throws -> [StoredRateRow] {
        let table = VerifiedRateTable()
        let rows = try reader.prepareRowIterator("""
        SELECT
            currency,
            rateProto
        FROM
            verified_rate;
        """)
        return try rows.map { row in
            StoredRateRow(
                currency: row[table.currency],
                rateProto: row[table.rateProto]
            )
        }
    }

    // MARK: - Verified Reserves -

    public func writeReserves(_ rows: [StoredReserveRow]) throws {
        guard !rows.isEmpty else { return }
        let table = VerifiedReserveTable()
        try transaction(silent: true) { _ in
            for row in rows {
                try writer.run(
                    table.table.upsert(
                        table.mint <- row.mint,
                        table.reserveProto <- row.reserveProto,
                        onConflictOf: table.mint
                    )
                )
            }
        }
    }

    public func allReserves() throws -> [StoredReserveRow] {
        let table = VerifiedReserveTable()
        let rows = try reader.prepareRowIterator("""
        SELECT
            mint,
            reserveProto
        FROM
            verified_reserve;
        """)
        return try rows.map { row in
            StoredReserveRow(
                mint: row[table.mint],
                reserveProto: row[table.reserveProto]
            )
        }
    }
}
