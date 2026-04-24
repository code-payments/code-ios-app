//
//  Database+VerifiedProtosTests.swift
//  FlipcashTests
//

import Testing
import Foundation
@testable import Flipcash
import FlipcashCore

@Suite("Database+VerifiedProtos")
struct DatabaseVerifiedProtosTests {

    // MARK: - Rate Tests

    @Test("writeRates then read returns the same row")
    func rate_roundTrip() throws {
        let db = Database.mock
        let row = StoredRateRow(currency: "USD", rateProto: Data([0x01, 0x02, 0x03]))

        try db.writeRates([row])

        #expect(try db.readVerifiedRate(currency: "USD") == row)
    }

    @Test("writeRates upserts on the currency key")
    func rate_upsert() throws {
        let db = Database.mock
        try db.writeRates([StoredRateRow(currency: "USD", rateProto: Data([0x01]))])
        try db.writeRates([StoredRateRow(currency: "USD", rateProto: Data([0x02]))])

        #expect(try db.readVerifiedRate(currency: "USD")?.rateProto == Data([0x02]))
    }

    @Test("readVerifiedRate returns nil for missing currency")
    func rate_missing() throws {
        let db = Database.mock
        #expect(try db.readVerifiedRate(currency: "EUR") == nil)
    }

    @Test("allRates returns every row")
    func rate_readAll() throws {
        let db = Database.mock
        try db.writeRates([
            StoredRateRow(currency: "USD", rateProto: Data([0x01])),
            StoredRateRow(currency: "EUR", rateProto: Data([0x02])),
        ])

        #expect(Set(try db.allRates().map(\.currency)) == ["USD", "EUR"])
    }

    // MARK: - Reserve Tests

    @Test("writeReserves then read returns the same row")
    func reserve_roundTrip() throws {
        let db = Database.mock
        let row = StoredReserveRow(mint: "SomeBase58MintAddress", reserveProto: Data([0xaa, 0xbb]))

        try db.writeReserves([row])

        #expect(try db.readVerifiedReserve(mint: row.mint) == row)
    }

    @Test("writeReserves upserts on mint")
    func reserve_upsert() throws {
        let db = Database.mock
        let mint = "MintX"
        try db.writeReserves([StoredReserveRow(mint: mint, reserveProto: Data([0x01]))])
        try db.writeReserves([StoredReserveRow(mint: mint, reserveProto: Data([0x02]))])

        #expect(try db.readVerifiedReserve(mint: mint)?.reserveProto == Data([0x02]))
    }

    @Test("allReserves returns every row")
    func reserve_readAll() throws {
        let db = Database.mock
        try db.writeReserves([
            StoredReserveRow(mint: "A", reserveProto: Data([0x01])),
            StoredReserveRow(mint: "B", reserveProto: Data([0x02])),
        ])

        #expect(Set(try db.allReserves().map(\.mint)) == ["A", "B"])
    }
}
