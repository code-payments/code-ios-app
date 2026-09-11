//
//  Regression_6a4fde33e96556123eb1f0ec.swift
//  FlipcashTests
//
//  "Failed to persist conversation state [replace-feed]" — database is locked (code: 5).
//  One cold launch ran completeLogin five times for the same owner; each built a
//  SessionContainer with its own Database, so four writer Connections shared one
//  SQLite file. replaceConversationFeed ran a DEFERRED transaction that read before
//  it wrote: once a rival writer held the lock, the snapshot upgrade returned
//  SQLITE_BUSY immediately, bypassing the busy handler.
//
//  Fix: Container.databaseStore hands out one Database per owner, so repeat logins
//  share a single writer; read-then-write transactions take the write lock up front
//  with BEGIN IMMEDIATE.
//

import Foundation
import Testing
import FlipcashCore
import FlipcashStore
@testable import Flipcash

@MainActor
@Suite("Regression: 6a4fde3 – replace-feed fails SQLITE_BUSY against a rival writer", .bug("6a4fde33e96556123eb1f0ec"))
struct Regression_6a4fde3 {

    private func conversation(_ byte: UInt8) -> Conversation {
        Conversation(id: .test(byte), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 100))
    }

    @Test("replace-feed waits for a rival writer to commit instead of failing the snapshot upgrade")
    func replaceFeed_rivalWriterHoldsLock_waitsThenCommits() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        // Seed a row so the second feed has something to delete — the read-then-write path.
        try database.replaceConversationFeed([conversation(1)], type: .contactDm)

        // A second Database on the same file is exactly what each extra SessionContainer opened.
        let rival = try Database(url: url)
        try rival.writer.run("BEGIN IMMEDIATE TRANSACTION")
        let release = Task.detached {
            try await Task.delay(milliseconds: 200)
            try rival.writer.run("COMMIT TRANSACTION")
        }

        try database.replaceConversationFeed([conversation(2)], type: .contactDm)
        try await release.value

        let ids = try database.getConversations().map(\.id)
        #expect(ids == [.test(2)])
    }

    @Test("busy timeout is armed in seconds, not milliseconds")
    func busyTimeout_isTwoSeconds() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        #expect(try database.writer.busyTimeout == 2)
        #expect(try database.reader.busyTimeout == 2)
    }

    @Test("the store hands the same Database back for the same owner")
    func databaseStore_sameOwnerTwice_returnsOneInstance() throws {
        try withThrowawayOwner { owner in
            let store = DatabaseStore()
            let first = try store.database(for: owner)
            let second = try store.database(for: owner)
            #expect(first === second)
        }
    }

    @Test("the store keeps different owners apart")
    func databaseStore_twoOwners_returnsDistinctInstances() throws {
        try withThrowawayOwner { alice in
            try withThrowawayOwner { bob in
                let store = DatabaseStore()
                let alicesDatabase = try store.database(for: alice)
                let bobsDatabase = try store.database(for: bob)
                #expect(alicesDatabase !== bobsDatabase)
            }
        }
    }

    /// Runs `body` against a throwaway owner and removes the store it opens.
    ///
    /// `deleteStore` deliberately leaves the version file, so this removes it explicitly —
    /// otherwise a stale version file survives in the App Group container between runs.
    private func withThrowawayOwner(_ body: (PublicKey) throws -> Void) throws {
        let owner = KeyPair.generate()!.publicKey
        let files = StoreLocation.resolved().files(owner: owner)
        defer {
            try? Database.deleteStore(files: files)
            try? FileManager.default.removeItem(at: files.version)
        }
        try body(owner)
    }
}
