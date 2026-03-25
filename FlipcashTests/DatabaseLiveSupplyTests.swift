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

    /// Creates a fresh in-memory database for test isolation
    private static func makeDatabase() -> Database {
        try! Database(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("test-\(UUID().uuidString).sqlite"))
    }

    /// Alias for the shared test helper
    private static func makeLaunchpadMint(
        address: PublicKey = .jeffy,
        supplyFromBonding: UInt64 = 50_000 * 10_000_000_000
    ) -> MintMetadata {
        .makeLaunchpad(address: address, supplyFromBonding: supplyFromBonding)
    }

    // MARK: - updateLiveSupply Tests

    @Test("updateLiveSupply inserts new rows")
    func updateLiveSupply_insertsNew() throws {
        let db = Self.makeDatabase()
        let mint = PublicKey.jeffy
        let supply: UInt64 = 100_000

        try db.updateLiveSupply(
            updates: [ReserveStateUpdate(mint: mint, supplyFromBonding: supply)],
            date: .now
        )

        // Verify by reading mint_live directly via raw SQL
        let table = MintLiveTable()
        let rows = try db.reader.prepareRowIterator(
            table.table.filter(table.mint == mint)
        )
        let results = try Array(rows)
        #expect(results.count == 1)
        #expect(results[0][table.supplyFromBonding] == supply)
    }

    @Test("updateLiveSupply overwrites existing rows")
    func updateLiveSupply_overwrites() throws {
        let db = Self.makeDatabase()
        let mint = PublicKey.jeffy

        try db.updateLiveSupply(
            updates: [ReserveStateUpdate(mint: mint, supplyFromBonding: 100)],
            date: .now
        )

        try db.updateLiveSupply(
            updates: [ReserveStateUpdate(mint: mint, supplyFromBonding: 999)],
            date: .now
        )

        let table = MintLiveTable()
        let rows = try db.reader.prepareRowIterator(
            table.table.filter(table.mint == mint)
        )
        let results = try Array(rows)
        #expect(results.count == 1)
        #expect(results[0][table.supplyFromBonding] == 999)
    }

    // MARK: - getBalances COALESCE Tests

    @Test("getBalances returns mint_live supply when it exists")
    func getBalances_prefersLiveSupply() throws {
        let db = Self.makeDatabase()
        let mint = PublicKey.jeffy
        let mintSupply: UInt64 = 50_000 * 10_000_000_000
        let liveSupply: UInt64 = 60_000 * 10_000_000_000

        // Insert mint metadata with original supply
        let metadata = Self.makeLaunchpadMint(address: mint, supplyFromBonding: mintSupply)
        try db.insert(mints: [metadata], date: .now)

        // Insert balance row
        try db.insertBalance(quarks: 1_000_000_000_000, mint: mint, costBasis: 0, date: .now)

        // Update live supply to a different value
        try db.updateLiveSupply(
            updates: [ReserveStateUpdate(mint: mint, supplyFromBonding: liveSupply)],
            date: .now
        )

        let balances = try db.getBalances()
        #expect(balances.count == 1)
        #expect(balances[0].supplyFromBonding == liveSupply)
    }

    @Test("getBalances falls back to mint table supply when no mint_live row exists")
    func getBalances_fallsBackToMintSupply() throws {
        let db = Self.makeDatabase()
        let mint = PublicKey.jeffy
        let mintSupply: UInt64 = 50_000 * 10_000_000_000

        // Insert mint metadata (which also seeds mint_live via insert(mint:date:))
        let metadata = Self.makeLaunchpadMint(address: mint, supplyFromBonding: mintSupply)
        try db.insert(mints: [metadata], date: .now)

        // Delete the mint_live row to simulate no live data
        let liveTable = MintLiveTable()
        try db.writer.run(liveTable.table.filter(liveTable.mint == mint).delete())

        // Insert balance row
        try db.insertBalance(quarks: 1_000_000_000_000, mint: mint, costBasis: 0, date: .now)

        let balances = try db.getBalances()
        #expect(balances.count == 1)
        #expect(balances[0].supplyFromBonding == mintSupply)
    }

    // MARK: - getMintMetadata COALESCE Tests

    @Test("getMintMetadata returns mint_live supply when it exists")
    func getMintMetadata_prefersLiveSupply() throws {
        let db = Self.makeDatabase()
        let mint = PublicKey.jeffy
        let mintSupply: UInt64 = 50_000 * 10_000_000_000
        let liveSupply: UInt64 = 75_000 * 10_000_000_000

        let metadata = Self.makeLaunchpadMint(address: mint, supplyFromBonding: mintSupply)
        try db.insert(mints: [metadata], date: .now)

        // Overwrite live supply
        try db.updateLiveSupply(
            updates: [ReserveStateUpdate(mint: mint, supplyFromBonding: liveSupply)],
            date: .now
        )

        let stored = try db.getMintMetadata(mint: mint)
        #expect(stored != nil)
        #expect(stored?.supplyFromBonding == liveSupply)
    }

    @Test("getMintMetadata falls back to mint table supply when no mint_live row")
    func getMintMetadata_fallsBackToMintSupply() throws {
        let db = Self.makeDatabase()
        let mint = PublicKey.jeffy
        let mintSupply: UInt64 = 50_000 * 10_000_000_000

        let metadata = Self.makeLaunchpadMint(address: mint, supplyFromBonding: mintSupply)
        try db.insert(mints: [metadata], date: .now)

        // Delete the mint_live row
        let liveTable = MintLiveTable()
        try db.writer.run(liveTable.table.filter(liveTable.mint == mint).delete())

        let stored = try db.getMintMetadata(mint: mint)
        #expect(stored != nil)
        #expect(stored?.supplyFromBonding == mintSupply)
    }

    // MARK: - insert(mints:) Seeding Tests

    @Test("insert(mints:) seeds mint_live for launchpad currencies")
    func insertMints_seedsLiveTable() throws {
        let db = Self.makeDatabase()
        let mint = PublicKey.jeffy
        let supply: UInt64 = 42_000 * 10_000_000_000

        let metadata = Self.makeLaunchpadMint(address: mint, supplyFromBonding: supply)
        try db.insert(mints: [metadata], date: .now)

        let table = MintLiveTable()
        let rows = try db.reader.prepareRowIterator(
            table.table.filter(table.mint == mint)
        )
        let results = try Array(rows)
        #expect(results.count == 1)
        #expect(results[0][table.supplyFromBonding] == supply)
    }

    @Test("insert(mints:) does not seed mint_live for non-launchpad currencies")
    func insertMints_doesNotSeedForNonLaunchpad() throws {
        let db = Self.makeDatabase()

        // Insert USDF which has no launchpadMetadata
        try db.insert(mints: [.usdf], date: .now)

        let table = MintLiveTable()
        let rows = try db.reader.prepareRowIterator(table.table)
        let results = try Array(rows)
        #expect(results.isEmpty)
    }
}
