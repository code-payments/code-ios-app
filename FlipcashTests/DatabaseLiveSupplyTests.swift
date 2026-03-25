//
//  DatabaseLiveSupplyTests.swift
//  FlipcashTests
//
//  Created on 2026-03-24.
//

import Foundation
import Testing
import FlipcashCore
import SQLite
@testable import Flipcash

@Suite(.serialized)
struct DatabaseLiveSupplyTests {

    // MARK: - Helpers

    private static func makeDatabase() -> Database {
        try! Database(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("test-\(UUID().uuidString).sqlite"))
    }

    private static func makeLaunchpadMint(
        address: PublicKey = .jeffy,
        supplyFromBonding: UInt64 = 50_000 * 10_000_000_000
    ) -> MintMetadata {
        .makeLaunchpad(address: address, supplyFromBonding: supplyFromBonding)
    }

    // MARK: - updateLiveSupply Tests

    @Test("updateLiveSupply updates supplyFromBonding in mint table")
    func updateLiveSupply_updatesMintTable() throws {
        let db = Self.makeDatabase()
        let mint = PublicKey.jeffy
        let originalSupply: UInt64 = 50_000 * 10_000_000_000
        let newSupply: UInt64 = 60_000 * 10_000_000_000

        let metadata = Self.makeLaunchpadMint(address: mint, supplyFromBonding: originalSupply)
        try db.insert(mints: [metadata], date: .now)
        try db.insertBalance(quarks: 1_000_000_000_000, mint: mint, costBasis: 0, date: .now)

        // Verify original supply
        let before = try db.getBalances()
        #expect(before.first?.supplyFromBonding == originalSupply)

        // Update via streaming path
        try db.updateLiveSupply(
            updates: [ReserveStateUpdate(mint: mint, supplyFromBonding: newSupply)],
            date: .now
        )

        // Verify updated supply
        let after = try db.getBalances()
        #expect(after.first?.supplyFromBonding == newSupply)
    }

    @Test("updateLiveSupply overwrites on repeated calls")
    func updateLiveSupply_overwrites() throws {
        let db = Self.makeDatabase()
        let mint = PublicKey.jeffy

        let metadata = Self.makeLaunchpadMint(address: mint)
        try db.insert(mints: [metadata], date: .now)

        try db.updateLiveSupply(
            updates: [ReserveStateUpdate(mint: mint, supplyFromBonding: 100)],
            date: .now
        )

        try db.updateLiveSupply(
            updates: [ReserveStateUpdate(mint: mint, supplyFromBonding: 999)],
            date: .now
        )

        let stored = try db.getMintMetadata(mint: mint)
        #expect(stored?.supplyFromBonding == 999)
    }

    @Test("getBalances reflects live supply update")
    func getBalances_reflectsLiveUpdate() throws {
        let db = Self.makeDatabase()
        let mint = PublicKey.jeffy
        let liveSupply: UInt64 = 75_000 * 10_000_000_000

        let metadata = Self.makeLaunchpadMint(address: mint)
        try db.insert(mints: [metadata], date: .now)
        try db.insertBalance(quarks: 1_000_000_000_000, mint: mint, costBasis: 0, date: .now)

        try db.updateLiveSupply(
            updates: [ReserveStateUpdate(mint: mint, supplyFromBonding: liveSupply)],
            date: .now
        )

        let balances = try db.getBalances()
        #expect(balances.count == 1)
        #expect(balances[0].supplyFromBonding == liveSupply)
    }

    @Test("getMintMetadata reflects live supply update")
    func getMintMetadata_reflectsLiveUpdate() throws {
        let db = Self.makeDatabase()
        let mint = PublicKey.jeffy
        let liveSupply: UInt64 = 80_000 * 10_000_000_000

        let metadata = Self.makeLaunchpadMint(address: mint)
        try db.insert(mints: [metadata], date: .now)

        try db.updateLiveSupply(
            updates: [ReserveStateUpdate(mint: mint, supplyFromBonding: liveSupply)],
            date: .now
        )

        let stored = try db.getMintMetadata(mint: mint)
        #expect(stored != nil)
        #expect(stored?.supplyFromBonding == liveSupply)
    }
}
