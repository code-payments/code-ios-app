//
//  DatabaseMintUpsertTests.swift
//  FlipcashTests
//
//  Created on 2026-04-01.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite("Mint upsert preserves supplyFromBonding")
struct DatabaseMintUpsertTests {

    // MARK: - Helpers

    private static func makeDatabase() throws -> Database {
        try Database.makeTemp()
    }

    /// A mint WITHOUT launchpadMetadata — simulates what fetchMints()
    /// returns when the server omits bonding curve data.
    private static func makeStaticMint(address: PublicKey = .jeffy) -> MintMetadata {
        MintMetadata(
            address: address,
            decimals: 10,
            name: "Test Token",
            symbol: "TEST",
            description: "A test token",
            imageURL: nil,
            vmMetadata: VMMetadata(
                vm: .usdc,
                authority: .usdcAuthority,
                lockDurationInDays: 21
            ),
            launchpadMetadata: nil
        )
    }

    // MARK: - Tests

    @Test("Upserting mint without launchpadMetadata preserves existing supplyFromBonding")
    func upsertWithoutLaunchpad_preservesSupply() throws {
        let db = try Self.makeDatabase()
        let mint = PublicKey.jeffy
        let supply: UInt64 = 50_000 * 10_000_000_000

        let original = MintMetadata.makeLaunchpad(address: mint, supplyFromBonding: supply)
        try db.insert(mints: [original], date: .now)

        let before = try #require(try db.getMintMetadata(mint: mint))
        #expect(before.supplyFromBonding == supply)

        // Re-insert the same mint WITHOUT launchpadMetadata (simulates fetchMints() response)
        let withoutLaunchpad = Self.makeStaticMint(address: mint)
        try db.insert(mints: [withoutLaunchpad], date: .now)

        // Supply must be preserved, not NULLed out
        let after = try #require(try db.getMintMetadata(mint: mint))
        #expect(after.supplyFromBonding == supply)
    }

    @Test("Upserting mint with launchpadMetadata updates supplyFromBonding")
    func upsertWithLaunchpad_updatesSupply() throws {
        let db = try Self.makeDatabase()
        let mint = PublicKey.jeffy
        let oldSupply: UInt64 = 50_000 * 10_000_000_000
        let newSupply: UInt64 = 75_000 * 10_000_000_000

        let original = MintMetadata.makeLaunchpad(address: mint, supplyFromBonding: oldSupply)
        try db.insert(mints: [original], date: .now)

        let updated = MintMetadata.makeLaunchpad(address: mint, supplyFromBonding: newSupply)
        try db.insert(mints: [updated], date: .now)

        let stored = try #require(try db.getMintMetadata(mint: mint))
        #expect(stored.supplyFromBonding == newSupply)
    }

    @Test("Live supply update is not overwritten by mint upsert without launchpadMetadata")
    func liveSupplyNotOverwrittenByStaticUpsert() throws {
        let db = try Self.makeDatabase()
        let mint = PublicKey.jeffy
        let initialSupply: UInt64 = 50_000 * 10_000_000_000
        let liveSupply: UInt64 = 80_000 * 10_000_000_000

        let original = MintMetadata.makeLaunchpad(address: mint, supplyFromBonding: initialSupply)
        try db.insert(mints: [original], date: .now)

        // Live stream delivers fresh supply
        try db.updateLiveSupply(
            updates: [ReserveStateUpdate(mint: mint, supplyFromBonding: liveSupply)],
            date: .now
        )

        // fetchMints() response re-inserts mint WITHOUT launchpadMetadata
        let withoutLaunchpad = Self.makeStaticMint(address: mint)
        try db.insert(mints: [withoutLaunchpad], date: .now)

        // Live supply must survive the upsert
        let stored = try #require(try db.getMintMetadata(mint: mint))
        #expect(stored.supplyFromBonding == liveSupply)
    }

    @Test("Balance is visible after mint upsert without launchpadMetadata")
    func balanceVisibleAfterStaticUpsert() throws {
        let db = try Self.makeDatabase()
        let mint = PublicKey.jeffy
        let supply: UInt64 = 50_000 * 10_000_000_000
        let quarks: UInt64 = 1_000_000_000_000

        let original = MintMetadata.makeLaunchpad(address: mint, supplyFromBonding: supply)
        try db.insert(mints: [original], date: .now)
        try db.insertBalance(quarks: quarks, mint: mint, costBasis: 0, date: .now)

        let before = try db.getBalances()
        try #require(before.count == 1)

        // fetchMints() upserts without launchpadMetadata
        let withoutLaunchpad = Self.makeStaticMint(address: mint)
        try db.insert(mints: [withoutLaunchpad], date: .now)

        // Balance must still be readable (getBalances must not throw)
        let after = try db.getBalances()
        #expect(after.count == 1)
        #expect(after[0].quarks == quarks)
        #expect(after[0].supplyFromBonding == supply)
    }
}
