//
//  Database+VerifiedProtos.swift
//  Flipcash
//

import Foundation
import FlipcashCore
import SQLite

extension Database: VerifiedProtoStore {

    // MARK: - Verified Rates -

    public func writeRate(_ row: StoredRateRow) throws {
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

    public func allRates() throws -> [StoredRateRow] {
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
            StoredRateRow(
                currency:   row[table.currency],
                rateProto:  row[table.rateProto],
                receivedAt: row[table.receivedAt]
            )
        }
    }

    func readVerifiedRate(currency: String) throws -> StoredRateRow? {
        let table = VerifiedRateTable()
        let query = table.table.filter(table.currency == currency)
        guard let row = try reader.pluck(query) else { return nil }
        return StoredRateRow(
            currency:   row[table.currency],
            rateProto:  row[table.rateProto],
            receivedAt: row[table.receivedAt]
        )
    }

    // MARK: - Verified Reserves -

    public func writeReserve(_ row: StoredReserveRow) throws {
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

    public func allReserves() throws -> [StoredReserveRow] {
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
            StoredReserveRow(
                mint:         row[table.mint],
                reserveProto: row[table.reserveProto],
                receivedAt:   row[table.receivedAt]
            )
        }
    }

    func readVerifiedReserve(mint: String) throws -> StoredReserveRow? {
        let table = VerifiedReserveTable()
        let query = table.table.filter(table.mint == mint)
        guard let row = try reader.pluck(query) else { return nil }
        return StoredReserveRow(
            mint:         row[table.mint],
            reserveProto: row[table.reserveProto],
            receivedAt:   row[table.receivedAt]
        )
    }
}
