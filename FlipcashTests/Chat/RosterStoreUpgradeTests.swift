//
//  RosterStoreUpgradeTests.swift
//  FlipcashTests
//

import Testing
import Foundation
import FlipcashCore
import FlipcashStore
import SQLite
@testable import Flipcash

/// The roster tables arrive without a schema bump, so an existing store must gain them on open
/// with its data intact, and the version gate must still behave as it did.
@Suite("Roster tables on an existing store")
struct RosterStoreUpgradeTests {

    private static let rosterTables = [RosterMemberTable.name, RosterTokenTable.name, RosterSyncTable.name]

    @Test("Opening a store from before the roster tables keeps its data and adds them")
    func keepsDataAndAddsTables() throws {
        let url = try RosterStoreFixture.makeStoreWithoutRosterTables()
        defer { Database.removeTemp(at: url) }
        let before = try RosterStoreFixture.rowCounts(at: url)
        #expect(before.conversations == 2)
        #expect(before.messages == 3)
        #expect(try RosterStoreFixture.tableNames(at: url).isDisjoint(with: Self.rosterTables))

        let database = try Database(url: url)
        try database.close()

        #expect(try RosterStoreFixture.rowCounts(at: url) == before)
        #expect(try RosterStoreFixture.tableNames(at: url).isSuperset(of: Self.rosterTables))
        #expect(try RosterStoreFixture.rosterRowCount(at: url) == 0)
    }

    @Test("Opening the upgraded store again changes nothing")
    func secondOpenIsANoOp() throws {
        let url = try RosterStoreFixture.makeStoreWithoutRosterTables()
        defer { Database.removeTemp(at: url) }

        try Database(url: url).close()
        let first = try RosterStoreFixture.rowCounts(at: url)
        let schema = try RosterStoreFixture.schemaSQL(at: url)

        try Database(url: url).close()

        #expect(try RosterStoreFixture.rowCounts(at: url) == first)
        #expect(try RosterStoreFixture.schemaSQL(at: url) == schema)
    }

    @Test("A store recorded at the current version is kept")
    func currentVersionKeepsStore() throws {
        let (files, root) = try Self.makeStore(recordedVersion: Database.schemaVersion)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(try Database.discardStoreIfOutdated(files: files) == false)
        #expect(FileManager.default.fileExists(atPath: files.database.path))
    }

    @Test("A store recorded above the code's version is kept, not deleted")
    func newerVersionKeepsStore() throws {
        let (files, root) = try Self.makeStore(recordedVersion: Database.schemaVersion + 1)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(try Database.discardStoreIfOutdated(files: files) == false)
        #expect(FileManager.default.fileExists(atPath: files.database.path))
        #expect(try Database.userVersion(files: files) == Database.schemaVersion + 1)
    }

    @Test("A later bump still deletes the whole store, roster tables included")
    func laterBumpDeletesStore() throws {
        let (files, root) = try Self.makeStore(recordedVersion: Database.schemaVersion)
        defer { try? FileManager.default.removeItem(at: root) }
        let bumped = Database.schemaVersion + 1

        #expect(try Database.discardStoreIfOutdated(files: files, schemaVersion: bumped))
        #expect(!FileManager.default.fileExists(atPath: files.database.path))
        #expect(try Database.userVersion(files: files) == bumped)

        let reopened = try Database(url: files.database)
        try reopened.close()
        #expect(try RosterStoreFixture.rowCounts(at: files.database) == .init(conversations: 0, messages: 0))
    }

    /// A full current-schema store with data in it, recorded at `recordedVersion`.
    private static func makeStore(recordedVersion: Int) throws -> (StoreLocation.Files, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("roster-upgrade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let files = StoreLocation(directory: root, legacyDirectory: root, isShared: true).files(owner: try PublicKey(Data(repeating: 9, count: 32)))
        let database = try Database(url: files.database)
        try RosterStoreFixture.seed(database)
        try database.close()
        try Database.setUserVersion(version: recordedVersion, files: files)
        return (files, root)
    }
}

/// Builds stores shaped like the ones already on devices, which predate the roster tables.
enum RosterStoreFixture {

    struct RowCounts: Equatable {
        let conversations: Int
        let messages: Int
    }

    /// A store with two conversations and three messages, and the roster tables dropped.
    static func makeStoreWithoutRosterTables() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("roster-v43-\(UUID().uuidString).sqlite")
        let database = try Database(url: url)
        try seed(database)
        try database.close()

        let connection = try Connection(url.path)
        for table in [RosterMemberTable.name, RosterTokenTable.name, RosterSyncTable.name] {
            try connection.run("DROP TABLE \(table)")
        }
        return url
    }

    static func seed(_ database: Database) throws {
        for (index, id) in [ConversationID.test(1), ConversationID.test(2)].enumerated() {
            try database.upsertConversation(Conversation(id: id, members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: Double(index))))
        }
        try database.upsertConversationMessages([
            ConversationMessage(id: MessageID(value: 1), senderID: nil, content: .text("one"), date: Date(timeIntervalSince1970: 10), unreadSeq: 1),
            ConversationMessage(id: MessageID(value: 2), senderID: nil, content: .text("two"), date: Date(timeIntervalSince1970: 20), unreadSeq: 2),
        ], conversationID: .test(1))
        try database.upsertConversationMessages([
            ConversationMessage(id: MessageID(value: 3), senderID: nil, content: .text("three"), date: Date(timeIntervalSince1970: 30), unreadSeq: 1),
        ], conversationID: .test(2))
    }

    static func rowCounts(at url: URL) throws -> RowCounts {
        let connection = try Connection(url.path, readonly: true)
        return RowCounts(
            conversations: Int(try connection.scalar("SELECT count(*) FROM \(ConversationTable.name)") as! Int64),
            messages: Int(try connection.scalar("SELECT count(*) FROM \(ConversationMessageTable.name)") as! Int64)
        )
    }

    static func rosterRowCount(at url: URL) throws -> Int {
        let connection = try Connection(url.path, readonly: true)
        var total: Int64 = 0
        for table in [RosterMemberTable.name, RosterTokenTable.name, RosterSyncTable.name] {
            total += try connection.scalar("SELECT count(*) FROM \(table)") as! Int64
        }
        return Int(total)
    }

    static func tableNames(at url: URL) throws -> Set<String> {
        let connection = try Connection(url.path, readonly: true)
        return Set(try connection.prepare("SELECT name FROM sqlite_master WHERE type = 'table'").compactMap { $0[0] as? String })
    }

    static func schemaSQL(at url: URL) throws -> [String] {
        let connection = try Connection(url.path, readonly: true)
        return try connection.prepare("SELECT sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY name").compactMap { $0[0] as? String }
    }
}
