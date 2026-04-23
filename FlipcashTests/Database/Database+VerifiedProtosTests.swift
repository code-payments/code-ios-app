//
//  Database+VerifiedProtosTests.swift
//  FlipcashTests
//

import Testing
import Foundation
@testable import Flipcash

@Suite("Database+VerifiedProtos")
struct DatabaseVerifiedProtosTests {

    // MARK: - Helpers

    private static func makeDatabase() throws -> Database {
        try Database(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("test-\(UUID().uuidString).sqlite"))
    }

    // MARK: - Rate Tests

    @Test("writeVerifiedRate then read returns the same row")
    func rate_roundTrip() throws {
        let db = try Self.makeDatabase()
        let proto = Data([0x01, 0x02, 0x03])
        let received = Date(timeIntervalSince1970: 1_000)

        try db.writeVerifiedRate(
            StoredVerifiedRate(currency: "USD", rateProto: proto, receivedAt: received)
        )

        let loaded = try db.readVerifiedRate(currency: "USD")
        #expect(loaded == StoredVerifiedRate(currency: "USD", rateProto: proto, receivedAt: received))
    }

    @Test("writeVerifiedRate upserts on the currency key")
    func rate_upsert() throws {
        let db = try Self.makeDatabase()
        try db.writeVerifiedRate(StoredVerifiedRate(currency: "USD", rateProto: Data([0x01]), receivedAt: Date(timeIntervalSince1970: 1_000)))
        try db.writeVerifiedRate(StoredVerifiedRate(currency: "USD", rateProto: Data([0x02]), receivedAt: Date(timeIntervalSince1970: 2_000)))

        let loaded = try db.readVerifiedRate(currency: "USD")
        #expect(loaded?.rateProto == Data([0x02]))
        #expect(loaded?.receivedAt == Date(timeIntervalSince1970: 2_000))
    }

    @Test("readVerifiedRate returns nil for missing currency")
    func rate_missing() throws {
        let db = try Self.makeDatabase()
        #expect(try db.readVerifiedRate(currency: "EUR") == nil)
    }

    @Test("readAllVerifiedRates returns every row")
    func rate_readAll() throws {
        let db = try Self.makeDatabase()
        try db.writeVerifiedRate(StoredVerifiedRate(currency: "USD", rateProto: Data([0x01]), receivedAt: Date(timeIntervalSince1970: 1_000)))
        try db.writeVerifiedRate(StoredVerifiedRate(currency: "EUR", rateProto: Data([0x02]), receivedAt: Date(timeIntervalSince1970: 2_000)))

        let all = try db.readAllVerifiedRates()
        #expect(Set(all.map(\.currency)) == ["USD", "EUR"])
    }

    // MARK: - Reserve Tests

    @Test("writeVerifiedReserve then read returns the same row")
    func reserve_roundTrip() throws {
        let db = try Self.makeDatabase()
        let proto = Data([0xaa, 0xbb])
        let received = Date(timeIntervalSince1970: 500)
        let mint = "SomeBase58MintAddress"

        try db.writeVerifiedReserve(
            StoredVerifiedReserve(mint: mint, reserveProto: proto, receivedAt: received)
        )

        let loaded = try db.readVerifiedReserve(mint: mint)
        #expect(loaded == StoredVerifiedReserve(mint: mint, reserveProto: proto, receivedAt: received))
    }

    @Test("writeVerifiedReserve upserts on mint")
    func reserve_upsert() throws {
        let db = try Self.makeDatabase()
        let mint = "MintX"
        try db.writeVerifiedReserve(StoredVerifiedReserve(mint: mint, reserveProto: Data([0x01]), receivedAt: Date(timeIntervalSince1970: 1_000)))
        try db.writeVerifiedReserve(StoredVerifiedReserve(mint: mint, reserveProto: Data([0x02]), receivedAt: Date(timeIntervalSince1970: 2_000)))

        let loaded = try db.readVerifiedReserve(mint: mint)
        #expect(loaded?.reserveProto == Data([0x02]))
    }

    @Test("readAllVerifiedReserves returns every row")
    func reserve_readAll() throws {
        let db = try Self.makeDatabase()
        try db.writeVerifiedReserve(StoredVerifiedReserve(mint: "A", reserveProto: Data([0x01]), receivedAt: Date()))
        try db.writeVerifiedReserve(StoredVerifiedReserve(mint: "B", reserveProto: Data([0x02]), receivedAt: Date()))

        let all = try db.readAllVerifiedReserves()
        #expect(Set(all.map(\.mint)) == ["A", "B"])
    }
}
