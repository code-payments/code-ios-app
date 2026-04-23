//
//  Database+VerifiedProtos.swift
//  Flipcash
//

import Foundation
import SQLite

extension Database {

    // MARK: - Verified Rates -

    func writeVerifiedRate(_ row: StoredVerifiedRate) throws {
        let table = VerifiedRateTable()
        try writer.run(
            table.table.upsert(
                table.currency   <- row.currency,
                table.rateProto  <- row.rateProto,
                table.receivedAt <- row.receivedAt,
                onConflictOf: table.currency
            )
        )
    }

    func readVerifiedRate(currency: String) throws -> StoredVerifiedRate? {
        let table = VerifiedRateTable()
        let query = table.table.filter(table.currency == currency)
        guard let row = try reader.pluck(query) else { return nil }
        return StoredVerifiedRate(
            currency:   row[table.currency],
            rateProto:  row[table.rateProto],
            receivedAt: row[table.receivedAt]
        )
    }

    func readAllVerifiedRates() throws -> [StoredVerifiedRate] {
        let table = VerifiedRateTable()
        let rows = try reader.prepareRowIterator("""
        SELECT
            currency,
            rateProto,
            receivedAt
        FROM
            verified_rate;
        """)
        return try rows.map { row in
            StoredVerifiedRate(
                currency:   row[table.currency],
                rateProto:  row[table.rateProto],
                receivedAt: row[table.receivedAt]
            )
        }
    }

    // MARK: - Verified Reserves -

    func writeVerifiedReserve(_ row: StoredVerifiedReserve) throws {
        let table = VerifiedReserveTable()
        try writer.run(
            table.table.upsert(
                table.mint         <- row.mint,
                table.reserveProto <- row.reserveProto,
                table.receivedAt   <- row.receivedAt,
                onConflictOf: table.mint
            )
        )
    }

    func readVerifiedReserve(mint: String) throws -> StoredVerifiedReserve? {
        let table = VerifiedReserveTable()
        let query = table.table.filter(table.mint == mint)
        guard let row = try reader.pluck(query) else { return nil }
        return StoredVerifiedReserve(
            mint:         row[table.mint],
            reserveProto: row[table.reserveProto],
            receivedAt:   row[table.receivedAt]
        )
    }

    func readAllVerifiedReserves() throws -> [StoredVerifiedReserve] {
        let table = VerifiedReserveTable()
        let rows = try reader.prepareRowIterator("""
        SELECT
            mint,
            reserveProto,
            receivedAt
        FROM
            verified_reserve;
        """)
        return try rows.map { row in
            StoredVerifiedReserve(
                mint:         row[table.mint],
                reserveProto: row[table.reserveProto],
                receivedAt:   row[table.receivedAt]
            )
        }
    }
}
