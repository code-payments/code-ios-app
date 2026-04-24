//
//  Database+VerifiedProtosTestSupport.swift
//  FlipcashTests
//

import Foundation
@testable import Flipcash
import FlipcashCore
import SQLite

/// Single-row read helpers used only in tests. Production reads the whole
/// `verified_rate` / `verified_reserve` table at warm-load, so these don't
/// belong in the production layer.
extension Database {
    func readVerifiedRate(currency: String) throws -> StoredRateRow? {
        let table = VerifiedRateTable()
        let query = table.table.filter(table.currency == currency)
        guard let row = try reader.pluck(query) else { return nil }
        return StoredRateRow(
            currency: row[table.currency],
            rateProto: row[table.rateProto]
        )
    }

    func readVerifiedReserve(mint: String) throws -> StoredReserveRow? {
        let table = VerifiedReserveTable()
        let query = table.table.filter(table.mint == mint)
        guard let row = try reader.pluck(query) else { return nil }
        return StoredReserveRow(
            mint: row[table.mint],
            reserveProto: row[table.reserveProto]
        )
    }
}
