//
//  Database+MintUpsertTests.swift
//  FlipcashTests
//
//  Created on 2026-04-01.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite("Mint upsert round-trips")
struct DatabaseMintUpsertTests {

    // MARK: - Helpers

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
        let (db, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
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
        let (db, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
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
        let (db, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
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

    @Test("coreMintFees survives store → read → rebuilt metadata")
    func coreMintFees_storeAndRead_preservedInRebuiltMetadata() throws {
        let (db, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let fees = try PublicKey([UInt8](repeating: 7, count: 32))

        let original = MintMetadata.makeLaunchpad(coreMintFees: fees)
        try db.insert(mints: [original], date: .now)

        let stored = try #require(try db.getMintMetadata(mint: original.address))
        #expect(stored.coreMintFees == fees)

        let rebuilt = try #require(stored.metadata.launchpadMetadata)
        #expect(rebuilt.coreMintFees == fees)
    }

    @Test("createdAt survives store → read → rebuilt metadata")
    func createdAt_storeAndRead_preservedInRebuiltMetadata() throws {
        let (db, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let created = Date(timeIntervalSince1970: 1_700_000_000)

        let original = MintMetadata.makeLaunchpad(createdAt: created)
        try db.insert(mints: [original], date: .now)

        let stored = try #require(try db.getMintMetadata(mint: original.address))
        #expect(stored.createdAt == created)
        #expect(stored.metadata.createdAt == created)
    }

    // MARK: - Write Gating

    @Test("Re-inserting an identical mint leaves the writer change count untouched", .currencyInfoAppHang)
    func upsertIdenticalMint_isSilent() throws {
        let (db, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let original = MintMetadata.makeLaunchpad(createdAt: Date(timeIntervalSince1970: 1_700_000_000))

        try db.insert(mints: [original], date: .now)

        let before = db.writer.totalChanges
        try db.insert(mints: [original], date: .now + 60)
        #expect(db.writer.totalChanges == before)
    }

    @Test("Re-inserting an identical mint preserves the stored row", .currencyInfoAppHang)
    func upsertIdenticalMint_rowUnchanged() throws {
        let (db, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let original = MintMetadata.makeLaunchpad()

        try db.insert(mints: [original], date: .now)
        let stored = try #require(try db.getMintMetadata(mint: original.address))

        try db.insert(mints: [original], date: .now + 60)
        let after = try #require(try db.getMintMetadata(mint: original.address))
        #expect(after == stored)
    }

    @Test("A changed name still writes")
    func upsertChangedName_writes() throws {
        let (db, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let mint = PublicKey.jeffy

        try db.insert(mints: [.makeLaunchpad(address: mint)], date: .now)

        let renamed = MintMetadata.makeLaunchpad(address: mint, name: "Renamed Token")

        let before = db.writer.totalChanges
        try db.insert(mints: [renamed], date: .now + 60)
        #expect(db.writer.totalChanges > before)
        #expect(try db.getMintMetadata(mint: mint)?.name == "Renamed Token")
    }

    @Test("A changed bonding supply still writes")
    func upsertChangedSupply_writes() throws {
        let (db, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let mint = PublicKey.jeffy

        try db.insert(mints: [.makeLaunchpad(address: mint, supplyFromBonding: 100)], date: .now)

        let before = db.writer.totalChanges
        try db.insert(mints: [.makeLaunchpad(address: mint, supplyFromBonding: 999)], date: .now + 60)
        #expect(db.writer.totalChanges > before)
        #expect(try db.getMintMetadata(mint: mint)?.supplyFromBonding == 999)
    }

    @Test("A static re-upsert over a launchpad row still writes")
    func upsertStaticOverLaunchpad_writes() throws {
        let (db, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let mint = PublicKey.jeffy

        try db.insert(mints: [.makeLaunchpad(address: mint)], date: .now)

        let before = db.writer.totalChanges
        try db.insert(mints: [Self.makeStaticMint(address: mint)], date: .now + 60)
        #expect(db.writer.totalChanges > before)
    }

    @Test("Balance is visible after mint upsert without launchpadMetadata")
    func balanceVisibleAfterStaticUpsert() throws {
        let (db, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
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
