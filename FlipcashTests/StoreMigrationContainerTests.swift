//
//  StoreMigrationContainerTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import SQLite
import FlipcashCore
import FlipcashStore
@testable import Flipcash

/// The migration against the containers the app actually uses, rather than two temporary
/// directories standing in for them.
///
/// `StoreMigrationTests` covers the logic — interruption, sweeping, version adoption — with injected
/// paths. What it cannot cover is the part of a real upgrade that runs before any of that logic:
/// resolving the App Group container. If the entitlement is not active at runtime,
/// `StoreLocation.resolved` falls back to Application Support, both sides name the same file, the
/// migration correctly reports `.notNeeded`, and the extension silently never sees the store. A test
/// that builds its own `StoreLocation` cannot see that failure.
///
/// Every file here is named from a random owner key. Store paths are owner-scoped
/// (`flipcash-<base58>.sqlite`), so nothing here can name a real account's store even though it sits
/// in the real directories, and each test removes what it wrote.
@Suite("Store migration, real containers", .serialized)
struct StoreMigrationContainerTests {

    /// A key no account holds, so these file names cannot collide with a real store.
    private func makeOwner() throws -> PublicKey {
        var bytes = Data(count: 32)
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: .min ... .max)
        }
        return try PublicKey(bytes)
    }

    /// The shape a shipped build leaves in Application Support: a WAL-mode store with one row, and
    /// the schema version recorded beside it under the name that build writes.
    ///
    /// Scoped so the connection closes before the migration runs. A live connection would keep the
    /// `-shm` on disk and the checkpoint would have company.
    private func seedLegacyStore(at files: StoreLocation.Files, value: String) throws {
        let connection = try Connection(files.database.path)
        try connection.run("PRAGMA journal_mode = WAL;")
        try connection.run("CREATE TABLE probe (id INTEGER PRIMARY KEY, value TEXT);")
        try connection.run("INSERT INTO probe (value) VALUES (?);", value)
        try Database.setUserVersion(version: 35, files: files)
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func remove(_ groups: StoreLocation.Files...) {
        for group in groups {
            for url in [group.database, group.wal, group.shm, group.version] {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    @Test("the App Group container resolves, so the store lands outside the app's own container")
    func containerResolves() {
        let location = StoreLocation.resolved()

        // The app's private container root, two levels above Application Support. Anything under it
        // is visible to this process only, which is the arrangement the move exists to end. The
        // container's own path is not checked for the group identifier: the simulator spells it out,
        // a device names the directory by UUID instead.
        let privateContainer = location.legacyDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        #expect(location.isShared)
        #expect(location.directory != location.legacyDirectory)
        #expect(!location.directory.path.hasPrefix(privateContainer.path))
    }

    @Test("a store in the real Application Support directory moves into the real App Group container")
    func upgradeMovesTheStore() throws {
        let owner = try makeOwner()
        let location = StoreLocation.resolved()
        let legacy = location.legacyFiles(owner: owner)
        let current = location.files(owner: owner)
        defer { remove(legacy, current) }

        try FileManager.default.createDirectory(
            at: location.legacyDirectory,
            withIntermediateDirectories: true
        )
        try seedLegacyStore(at: legacy, value: "survived-the-upgrade")

        let outcome = StoreMigration.migrateIfNeeded(owner: owner, location: location)

        #expect(outcome == .migrated)
        #expect(exists(current.database))
        #expect(!exists(legacy.database))
        #expect(!exists(legacy.version))

        // The recorded version has to arrive with the store. 35 is what the shipped build wrote from
        // its `SQLiteVersion` Info.plist key and what this build reads from `Database.schemaVersion`;
        // if the number did not travel, the launch that just migrated reads 0, decides the schema is
        // stale, and deletes the store it moved.
        let recorded = (try? Database.userVersion(files: current)) ?? 0
        #expect(recorded == 35)
        #expect(Database.schemaVersion <= recorded)

        // Reached through `Database`, which is how the app reads it — and a migrated store arrives as
        // a lone `.sqlite` with no `-shm`, the case that needs the writer opened before the reader.
        let database = try Database(url: current.database)
        defer { try? database.close() }
        let value = try database.reader.scalar("SELECT value FROM probe LIMIT 1;") as? String
        #expect(value == "survived-the-upgrade")
    }

    @Test("the extension opens the store the app migrated, at the path it resolves for itself")
    func extensionReachesTheMigratedStore() throws {
        let owner = try makeOwner()
        let location = StoreLocation.resolved()
        let legacy = location.legacyFiles(owner: owner)
        defer { remove(legacy, location.files(owner: owner)) }

        try FileManager.default.createDirectory(
            at: location.legacyDirectory,
            withIntermediateDirectories: true
        )
        try seedLegacyStore(at: legacy, value: "written-by-the-app")
        #expect(StoreMigration.migrateIfNeeded(owner: owner, location: location) == .migrated)

        // No location passed: `ExtensionStore` resolves the container itself, the way the notification
        // service extension does. That it finds this store is the whole point of the move.
        var read: String?
        let outcome = ExtensionStore.perform(owner: owner) { database in
            read = try database.reader.scalar("SELECT value FROM probe LIMIT 1;") as? String
            try database.writer.run("INSERT INTO probe (value) VALUES (?);", "written-by-the-extension")
        }

        #expect(outcome == .wrote)
        #expect(read == "written-by-the-app")

        // And back the other way: what the extension wrote is there for the app's next read.
        let database = try Database(url: location.files(owner: owner).database)
        defer { try? database.close() }
        let count = try database.reader.scalar("SELECT count(*) FROM probe;") as? Int64
        #expect(count == 2)
    }

    @Test("a push before the first migrated launch does not leave an empty store behind")
    func extensionCreatesNothing() throws {
        let owner = try makeOwner()
        let current = StoreLocation.resolved().files(owner: owner)
        defer { remove(current) }

        let outcome = ExtensionStore.perform(owner: owner) { _ in
            Issue.record("The body must not run when there is no store at the shared path.")
        }

        #expect(outcome == .noStore)
        #expect(!exists(current.database))
    }
}
