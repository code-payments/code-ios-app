//
//  Database+Rates.swift
//  Flipcash
//
//  Created by Claude on 2026-04-09.
//

import Foundation
import FlipcashCore
import SQLite

nonisolated extension Database {

    // MARK: - Get -

    /// Load all persisted display rates. Used by ``RatesController`` to
    /// rehydrate its in-memory cache on cold launch so screens render in
    /// the user's preferred currency before the live mint stream delivers
    /// its first batch.
    func getRates() throws -> [Rate] {
        let table = RateTable()

        let rows = try reader.prepareRowIterator("""
        SELECT
            r.data
        FROM
            rate r;
        """)

        return try rows.map { row in
            try JSONDecoder().decode(Rate.self, from: row[table.data])
        }
    }

    // MARK: - Upsert -

    /// Write through a batch of rates from the live mint stream. Each
    /// row is keyed by currency code, so repeated stream updates for the
    /// same currency replace the previous row in place.
    func upsertRates(_ rates: [Rate]) throws {
        guard !rates.isEmpty else { return }

        let table = RateTable()

        try transaction { _ in
            for rate in rates {
                let data = try JSONEncoder().encode(rate)
                try writer.run(
                    table.table.upsert(
                        table.currency <- rate.currency,
                        table.data     <- data,
                        onConflictOf: table.currency
                    )
                )
            }
        }
    }
}
