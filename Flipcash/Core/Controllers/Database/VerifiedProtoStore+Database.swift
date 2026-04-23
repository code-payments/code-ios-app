//
//  VerifiedProtoStore+Database.swift
//  Flipcash
//

import Foundation
import FlipcashCore

extension Database: VerifiedProtoStore {

    public func allRates() throws -> [StoredRateRow] {
        try readAllVerifiedRates().map {
            StoredRateRow(currency: $0.currency, rateProto: $0.rateProto, receivedAt: $0.receivedAt)
        }
    }

    public func allReserves() throws -> [StoredReserveRow] {
        try readAllVerifiedReserves().map {
            StoredReserveRow(mint: $0.mint, reserveProto: $0.reserveProto, receivedAt: $0.receivedAt)
        }
    }

    public func writeRate(_ row: StoredRateRow) throws {
        try writeVerifiedRate(
            StoredVerifiedRate(currency: row.currency, rateProto: row.rateProto, receivedAt: row.receivedAt)
        )
    }

    public func writeReserve(_ row: StoredReserveRow) throws {
        try writeVerifiedReserve(
            StoredVerifiedReserve(mint: row.mint, reserveProto: row.reserveProto, receivedAt: row.receivedAt)
        )
    }
}
