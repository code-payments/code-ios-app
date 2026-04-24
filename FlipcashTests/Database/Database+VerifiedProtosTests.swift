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

    @Test("writeRate then read returns the same row")
    func rate_roundTrip() throws {
        let db = try Database.makeIsolated()
        let proto = Data([0x01, 0x02, 0x03])
        let received = Date(timeIntervalSince1970: 1_000)

        try db.writeRate(
            StoredRateRow(currency: "USD", rateProto: proto, receivedAt: received)
        )

        let loaded = try db.readVerifiedRate(currency: "USD")
        #expect(loaded == StoredRateRow(currency: "USD", rateProto: proto, receivedAt: received))
    }

    @Test("writeRate upserts on the currency key")
    func rate_upsert() throws {
        let db = try Database.makeIsolated()
        try db.writeRate(StoredRateRow(currency: "USD", rateProto: Data([0x01]), receivedAt: Date(timeIntervalSince1970: 1_000)))
        try db.writeRate(StoredRateRow(currency: "USD", rateProto: Data([0x02]), receivedAt: Date(timeIntervalSince1970: 2_000)))

        let loaded = try db.readVerifiedRate(currency: "USD")
        #expect(loaded?.rateProto == Data([0x02]))
        #expect(loaded?.receivedAt == Date(timeIntervalSince1970: 2_000))
    }

    @Test("readVerifiedRate returns nil for missing currency")
    func rate_missing() throws {
        let db = try Database.makeIsolated()
        #expect(try db.readVerifiedRate(currency: "EUR") == nil)
    }

    @Test("allRates returns every row")
    func rate_readAll() throws {
        let db = try Database.makeIsolated()
        try db.writeRate(StoredRateRow(currency: "USD", rateProto: Data([0x01]), receivedAt: Date(timeIntervalSince1970: 1_000)))
        try db.writeRate(StoredRateRow(currency: "EUR", rateProto: Data([0x02]), receivedAt: Date(timeIntervalSince1970: 2_000)))

        let all = try db.allRates()
        #expect(Set(all.map(\.currency)) == ["USD", "EUR"])
    }

    // MARK: - Reserve Tests

    @Test("writeReserve then read returns the same row")
    func reserve_roundTrip() throws {
        let db = try Database.makeIsolated()
        let proto = Data([0xaa, 0xbb])
        let received = Date(timeIntervalSince1970: 500)
        let mint = "SomeBase58MintAddress"

        try db.writeReserve(
            StoredReserveRow(mint: mint, reserveProto: proto, receivedAt: received)
        )

        let loaded = try db.readVerifiedReserve(mint: mint)
        #expect(loaded == StoredReserveRow(mint: mint, reserveProto: proto, receivedAt: received))
    }

    @Test("writeReserve upserts on mint")
    func reserve_upsert() throws {
        let db = try Database.makeIsolated()
        let mint = "MintX"
        try db.writeReserve(StoredReserveRow(mint: mint, reserveProto: Data([0x01]), receivedAt: Date(timeIntervalSince1970: 1_000)))
        try db.writeReserve(StoredReserveRow(mint: mint, reserveProto: Data([0x02]), receivedAt: Date(timeIntervalSince1970: 2_000)))

        let loaded = try db.readVerifiedReserve(mint: mint)
        #expect(loaded?.reserveProto == Data([0x02]))
    }

    @Test("allReserves returns every row")
    func reserve_readAll() throws {
        let db = try Database.makeIsolated()
        try db.writeReserve(StoredReserveRow(mint: "A", reserveProto: Data([0x01]), receivedAt: Date()))
        try db.writeReserve(StoredReserveRow(mint: "B", reserveProto: Data([0x02]), receivedAt: Date()))

        let all = try db.allReserves()
        #expect(Set(all.map(\.mint)) == ["A", "B"])
    }
}
