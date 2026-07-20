//
//  Database+BalanceUpsertTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite("Balance upsert write gating")
struct DatabaseBalanceUpsertTests {

    @Test("Re-upserting identical balance values leaves the writer change count untouched")
    func insertBalance_identicalValues_isSilent() throws {
        let (db, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let mint = PublicKey.jeffy

        try db.insertBalance(quarks: 1_000, mint: mint, costBasis: 2.5, date: .now)

        let before = db.writer.totalChanges
        try db.insertBalance(quarks: 1_000, mint: mint, costBasis: 2.5, date: .now + 60)
        #expect(db.writer.totalChanges == before)
    }

    @Test("Changed quarks still update the stored balance")
    func insertBalance_changedQuarks_writes() throws {
        let (db, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let mint = PublicKey.jeffy

        try db.insert(mints: [.makeLaunchpad(address: mint)], date: .now)
        try db.insertBalance(quarks: 1_000, mint: mint, costBasis: 2.5, date: .now)

        let before = db.writer.totalChanges
        try db.insertBalance(quarks: 2_000, mint: mint, costBasis: 2.5, date: .now + 60)
        #expect(db.writer.totalChanges > before)
        #expect(try db.getBalances().first?.quarks == 2_000)
    }

    @Test("Changed cost basis still updates the stored balance")
    func insertBalance_changedCostBasis_writes() throws {
        let (db, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let mint = PublicKey.jeffy

        try db.insert(mints: [.makeLaunchpad(address: mint)], date: .now)
        try db.insertBalance(quarks: 1_000, mint: mint, costBasis: 2.5, date: .now)

        let before = db.writer.totalChanges
        try db.insertBalance(quarks: 1_000, mint: mint, costBasis: 3.0, date: .now + 60)
        #expect(db.writer.totalChanges > before)
        #expect(try db.getBalances().first?.costBasis == 3.0)
    }

    @Test("First insert of a new balance writes")
    func insertBalance_newRow_writes() throws {
        let (db, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }

        let before = db.writer.totalChanges
        try db.insertBalance(quarks: 1_000, mint: .jeffy, costBasis: 0, date: .now)
        #expect(db.writer.totalChanges > before)
    }
}
