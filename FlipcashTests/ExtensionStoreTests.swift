//
//  ExtensionStoreTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import SQLite
import FlipcashCore
import FlipcashStore
@testable import Flipcash

@Suite("Extension store writes")
struct ExtensionStoreTests {

    private let owner = try! PublicKey(Data(repeating: 9, count: 32))

    /// A location standing in for the App Group container. Both directories are the same here:
    /// these tests are about what happens once the store has arrived, not about the move.
    private func makeLocation() throws -> StoreLocation {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("extension-store-\(UUID().uuidString)")
        let group = root.appendingPathComponent("group")
        let support = root.appendingPathComponent("support")
        try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return StoreLocation(directory: group, legacyDirectory: support, isShared: true)
    }

    /// Creates the store the way a logged-in app leaves it: tables built, version recorded.
    private func seedStore(at location: StoreLocation, version: Int = Database.schemaVersion) throws {
        let files = location.files(owner: owner)
        let database = try Database(url: files.database)
        try database.close()
        try Database.setUserVersion(version: version, files: files)
    }

    private func message(id: UInt64, text: String, sequence: UInt64 = 1) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id),
            senderID: UUID(),
            content: .text(text),
            date: Date(timeIntervalSince1970: TimeInterval(id)),
            unreadSeq: id,
            eventSequence: sequence
        )
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - The guards -

    @Test("no store at the shared location is a no-op, and creates nothing")
    func missingStoreCreatesNothing() throws {
        let location = try makeLocation()
        let files = location.files(owner: owner)

        let outcome = ExtensionStore.perform(owner: owner, location: location) { _ in
            Issue.record("the body must not run without a store")
        }

        #expect(outcome == .noStore)
        // The point of the guard. An empty store here reads to `StoreMigration` as a finished
        // migration, which would make it delete the legacy store the user's history is still in.
        #expect(!exists(files.database))
        #expect(!exists(files.wal))
        #expect(!exists(files.version))
    }

    @Test("a store with no recorded version is left alone")
    func missingVersionFileIsSkipped() throws {
        let location = try makeLocation()
        let files = location.files(owner: owner)
        let database = try Database(url: files.database)
        try database.close()

        let outcome = ExtensionStore.perform(owner: owner, location: location) { _ in
            Issue.record("the body must not run without a recorded version")
        }

        #expect(outcome == .versionMismatch(recorded: nil))
    }

    @Test("a store recorded at an older schema is left for the app to rebuild")
    func olderSchemaIsSkipped() throws {
        let location = try makeLocation()
        try seedStore(at: location, version: Database.schemaVersion - 1)

        let outcome = ExtensionStore.perform(owner: owner, location: location) { _ in
            Issue.record("the body must not run against a stale schema")
        }

        #expect(outcome == .versionMismatch(recorded: Database.schemaVersion - 1))
    }

    @Test("a store recorded at a newer schema is left alone too")
    func newerSchemaIsSkipped() throws {
        // A user who installed a newer build and then downgraded. This build's `Schema` is the
        // older one, so writing through it could hit a column that no longer means what it did.
        let location = try makeLocation()
        try seedStore(at: location, version: Database.schemaVersion + 1)

        let outcome = ExtensionStore.perform(owner: owner, location: location) { _ in
            Issue.record("the body must not run against a newer schema")
        }

        #expect(outcome == .versionMismatch(recorded: Database.schemaVersion + 1))
    }

    // MARK: - Writing -

    @Test("messages written by the extension are there for the app to read")
    func writesAreVisibleToTheApp() throws {
        let location = try makeLocation()
        try seedStore(at: location)
        let conversationID = ConversationID.test(3)

        let outcome = ExtensionStore.perform(owner: owner, location: location) { database in
            try database.persistMessages(
                [message(id: 1, text: "first"), message(id: 2, text: "second")],
                cursor: 0,
                conversationID: conversationID
            )
        }
        #expect(outcome == .wrote)

        // Reopened the way the app opens it at login, which is the only read that matters.
        let app = try Database(url: location.files(owner: owner).database)
        let stored = try app.messagesWindow(conversationID: conversationID, limit: 10)
        #expect(stored.count == 2)
        #expect(stored.map(\.id.value).sorted() == [1, 2])
        try app.close()
    }

    @Test("the catch-up cursor does not move")
    func cursorIsNotAdvanced() throws {
        let location = try makeLocation()
        try seedStore(at: location)
        let conversationID = ConversationID.test(4)

        #expect(
            ExtensionStore.perform(owner: owner, location: location) { database in
                try database.persistMessages([message(id: 9, text: "preview")], cursor: 0, conversationID: conversationID)
            } == .wrote
        )

        // The extension fetched a bounded preview, not a delta. A cursor advanced to it would tell
        // the app it has everything up to that point and make the next sync skip the gap.
        let app = try Database(url: location.files(owner: owner).database)
        #expect(try app.catchupCursor(conversationID: conversationID) == 0)
        try app.close()
    }

    @Test("writing the same preview twice changes nothing")
    func repeatedWritesMerge() throws {
        let location = try makeLocation()
        try seedStore(at: location)
        let conversationID = ConversationID.test(5)
        let batch = [message(id: 1, text: "once"), message(id: 2, text: "twice")]

        for _ in 0..<3 {
            #expect(
                ExtensionStore.perform(owner: owner, location: location) { database in
                    try database.persistMessages(batch, cursor: 0, conversationID: conversationID)
                } == .wrote
            )
        }

        let app = try Database(url: location.files(owner: owner).database)
        #expect(try app.messagesWindow(conversationID: conversationID, limit: 10).count == 2)
        try app.close()
    }

    @Test("a stale re-delivery does not overwrite a newer stored message")
    func staleDeliveryLoses() throws {
        let location = try makeLocation()
        try seedStore(at: location)
        let conversationID = ConversationID.test(6)

        _ = ExtensionStore.perform(owner: owner, location: location) { database in
            try database.persistMessages([message(id: 1, text: "edited", sequence: 5)], cursor: 0, conversationID: conversationID)
        }
        _ = ExtensionStore.perform(owner: owner, location: location) { database in
            try database.persistMessages([message(id: 1, text: "original", sequence: 2)], cursor: 0, conversationID: conversationID)
        }

        let app = try Database(url: location.files(owner: owner).database)
        let stored = try app.messagesWindow(conversationID: conversationID, limit: 10)
        #expect(stored.count == 1)
        if case .text(let text) = stored.first?.content {
            #expect(text == "edited")
        } else {
            Issue.record("expected a text message")
        }
        try app.close()
    }

    // MARK: - Closing -

    @Test("the cycle leaves no write-ahead log behind")
    func storeIsCheckpointedAndClosed() throws {
        let location = try makeLocation()
        try seedStore(at: location)
        let files = location.files(owner: owner)

        #expect(
            ExtensionStore.perform(owner: owner, location: location) { database in
                try database.persistMessages([message(id: 1, text: "flushed")], cursor: 0, conversationID: .test(7))
            } == .wrote
        )

        // A truncating checkpoint ran and both connections were dropped, so anything left is empty.
        // A log with bytes in it would mean the extension went away still holding the store open —
        // the shape that gets a process killed with `0xdead10cc`.
        let walSize = (try? FileManager.default.attributesOfItem(atPath: files.wal.path)[.size] as? Int) ?? 0
        #expect(walSize == 0)
    }

    @Test("a throwing body still closes the store, and commits nothing")
    func failureStillCloses() throws {
        let location = try makeLocation()
        try seedStore(at: location)
        let conversationID = ConversationID.test(8)

        struct Boom: Error {}
        let outcome = ExtensionStore.perform(owner: owner, location: location) { database in
            try database.persistMessages([message(id: 1, text: "rolled back")], cursor: 0, conversationID: conversationID)
            throw Boom()
        }

        guard case .failed = outcome else {
            Issue.record("expected a failure, got \(outcome)")
            return
        }

        // `persistMessages` committed its own transaction before the throw, so the row is there.
        // What matters is that the store reopens at all, which it cannot if the cycle leaked a
        // connection or left the file locked.
        let app = try Database(url: location.files(owner: owner).database)
        #expect(try app.messagesWindow(conversationID: conversationID, limit: 10).count == 1)
        try app.close()
    }

    // MARK: - Contention -

    @Test("another process holding the write lock ends the cycle instead of waiting")
    func busyLockGivesUp() throws {
        let location = try makeLocation()
        try seedStore(at: location)
        let files = location.files(owner: owner)

        // Stands in for the app mid-transaction. `BEGIN EXCLUSIVE` takes the write lock and holds
        // it for as long as this connection is alive.
        let holder = try Connection(files.database.path)
        try holder.run("PRAGMA journal_mode = WAL;")
        try holder.run("BEGIN EXCLUSIVE;")
        defer { try? holder.run("ROLLBACK;") }

        let outcome = ExtensionStore.perform(owner: owner, location: location) { database in
            try database.persistMessages([message(id: 1, text: "contended")], cursor: 0, conversationID: .test(9))
        }

        #expect(outcome == .busy)
    }
}
