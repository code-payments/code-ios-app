//
//  StoreMigrationTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import SQLite
import FlipcashCore
import FlipcashStore
@testable import Flipcash

@Suite("Store migration")
struct StoreMigrationTests {

    private let owner = try! PublicKey(Data(repeating: 7, count: 32))

    /// A location whose two directories are both fresh and both empty, standing in for an App
    /// Group container and an Application Support directory.
    private func makeLocation() throws -> StoreLocation {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-\(UUID().uuidString)")
        let current = root.appendingPathComponent("group")
        let legacy = root.appendingPathComponent("support")
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        return StoreLocation(directory: current, legacyDirectory: legacy, isShared: true)
    }

    /// Writes a store at `url` with one row in it, and closes it again.
    private func seedStore(at url: URL, value: String) throws {
        let connection = try Connection(url.path)
        try connection.run("PRAGMA journal_mode = WAL;")
        try connection.run("CREATE TABLE probe (id INTEGER PRIMARY KEY, value TEXT);")
        try connection.run("INSERT INTO probe (value) VALUES (?);", value)
    }

    /// Read-write on purpose. A migrated store arrives as a lone `.sqlite` — the `-wal` was
    /// folded in and the `-shm` swept — and a read-only connection to a WAL-mode database with
    /// no `-shm` beside it fails with `unable to open database file`, because it cannot create
    /// the shared-memory file it needs. `Database` does not hit this: it opens its writer before
    /// its reader, and the writer creates the `-shm`.
    private func readProbe(at url: URL) throws -> String? {
        let connection = try Connection(url.path)
        return try connection.scalar("SELECT value FROM probe LIMIT 1;") as? String
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Migrating -

    @Test("a store in the old location moves, with its rows")
    func legacyStoreMoves() throws {
        let location = try makeLocation()
        let legacy = location.legacyFiles(owner: owner)
        let current = location.files(owner: owner)
        try seedStore(at: legacy.database, value: "carried-over")

        let outcome = StoreMigration.migrateIfNeeded(owner: owner, location: location)

        #expect(outcome == .migrated)
        #expect(exists(current.database))
        #expect(try readProbe(at: current.database) == "carried-over")
    }

    @Test("the app opens the migrated store through Database and reads it")
    func migratedStoreOpensThroughDatabase() throws {
        let location = try makeLocation()
        let legacy = location.legacyFiles(owner: owner)
        let current = location.files(owner: owner)
        try seedStore(at: legacy.database, value: "upgrade-path")

        #expect(StoreMigration.migrateIfNeeded(owner: owner, location: location) == .migrated)

        // Through the type the app actually uses, including its `createTablesIfNeeded` pass,
        // which is the step that would fail against a half-moved or truncated file. It also
        // covers the writer-before-reader ordering in `Database.init`: a freshly migrated store
        // has no `-shm`, and only a writer can create one.
        let database = try Database(url: current.database)
        let value = try database.reader.scalar("SELECT value FROM probe LIMIT 1;") as? String
        #expect(value == "upgrade-path")
    }

    @Test("nothing is left behind in the old location")
    func legacyLeftoversAreSwept() throws {
        let location = try makeLocation()
        let legacy = location.legacyFiles(owner: owner)
        try seedStore(at: legacy.database, value: "moved")
        try "4".write(to: legacy.version, atomically: true, encoding: .utf8)

        _ = StoreMigration.migrateIfNeeded(owner: owner, location: location)

        #expect(!exists(legacy.database))
        #expect(!exists(legacy.wal))
        #expect(!exists(legacy.shm))
        #expect(!exists(legacy.version))
    }

    /// The store is deleted and rebuilt whenever the recorded version is older than the build's,
    /// and a missing version file reads as 0. A migration that dropped the version file would
    /// therefore wipe the store it had just moved.
    @Test("the recorded version survives the move")
    func versionFileMovesWithTheStore() throws {
        let location = try makeLocation()
        let legacy = location.legacyFiles(owner: owner)
        let current = location.files(owner: owner)
        try seedStore(at: legacy.database, value: "row")
        try Database.setUserVersion(version: 9, files: legacy)

        _ = StoreMigration.migrateIfNeeded(owner: owner, location: location)

        #expect(try Database.userVersion(files: current) == 9)
    }

    @Test("a store with no recorded version still moves")
    func missingVersionFileIsNotAnError() throws {
        let location = try makeLocation()
        let legacy = location.legacyFiles(owner: owner)
        let current = location.files(owner: owner)
        try seedStore(at: legacy.database, value: "unversioned")

        #expect(StoreMigration.migrateIfNeeded(owner: owner, location: location) == .migrated)
        #expect(try readProbe(at: current.database) == "unversioned")
    }

    /// Rows sitting in the write-ahead log rather than the main database file are the reason the
    /// migration checkpoints before it moves anything.
    @Test("rows still in the write-ahead log arrive at the destination")
    func walContentsAreFoldedInBeforeTheMove() throws {
        let location = try makeLocation()
        let legacy = location.legacyFiles(owner: owner)
        let current = location.files(owner: owner)

        // Held open across the migration: SQLite folds the log back in when the last connection
        // to a store closes, so only a connection that is still open leaves a log on disk for
        // the migration to find.
        var writer: Connection? = try Connection(legacy.database.path)
        try writer?.run("PRAGMA journal_mode = WAL;")
        try writer?.run("CREATE TABLE probe (id INTEGER PRIMARY KEY, value TEXT);")
        try writer?.run("INSERT INTO probe (value) VALUES (?);", "in-the-log")
        #expect(exists(legacy.wal))

        let outcome = StoreMigration.migrateIfNeeded(owner: owner, location: location)
        #expect(outcome == .migrated)

        // Dropped before the read, which is the only reason this reads back at all. The
        // migration swept the legacy `-wal` and `-shm` out from under this connection, and the
        // moved file is the same inode it still points at, so a second connection opened
        // alongside it inherits that half-torn state and throws a disk I/O error. The app never
        // reaches this shape: it migrates at launch, before anything has the store open.
        writer = nil

        #expect(try readProbe(at: current.database) == "in-the-log")
    }

    // MARK: - Not migrating -

    @Test("no store in either place is nothing to do")
    func emptyDirectoriesAreNotNeeded() throws {
        let location = try makeLocation()

        #expect(StoreMigration.migrateIfNeeded(owner: owner, location: location) == .notNeeded)
    }

    /// When the App Group container does not resolve, `StoreLocation` falls back and both
    /// directories name the same paths. Moving a file onto itself fails.
    @Test("a fallback location has nothing to move")
    func identicalDirectoriesAreNotNeeded() throws {
        let base = try makeLocation().legacyDirectory
        let location = StoreLocation(directory: base, legacyDirectory: base, isShared: false)
        try seedStore(at: location.files(owner: owner).database, value: "in-place")

        #expect(StoreMigration.migrateIfNeeded(owner: owner, location: location) == .notNeeded)
        #expect(try readProbe(at: location.files(owner: owner).database) == "in-place")
    }

    @Test("a store already at the destination is kept, and the old one discarded")
    func destinationStoreWins() throws {
        let location = try makeLocation()
        let legacy = location.legacyFiles(owner: owner)
        let current = location.files(owner: owner)
        try seedStore(at: current.database, value: "current")
        try seedStore(at: legacy.database, value: "stale")

        let outcome = StoreMigration.migrateIfNeeded(owner: owner, location: location)

        #expect(outcome == .alreadyMigrated)
        #expect(try readProbe(at: current.database) == "current")
        #expect(!exists(legacy.database))
    }

    /// The half-completed move the ordering is designed around: the version file landed, the
    /// process died, the database is still in the old directory.
    @Test("a move interrupted after the version file finishes on the next run")
    func interruptedMoveResumes() throws {
        let location = try makeLocation()
        let legacy = location.legacyFiles(owner: owner)
        let current = location.files(owner: owner)
        try seedStore(at: legacy.database, value: "resumed")
        try Database.setUserVersion(version: 3, files: current)

        let outcome = StoreMigration.migrateIfNeeded(owner: owner, location: location)

        #expect(outcome == .migrated)
        #expect(try readProbe(at: current.database) == "resumed")
        #expect(try Database.userVersion(files: current) == 3)
    }

    /// A destination version file is the record of a move that already got that far, so a legacy
    /// one left beside it is stale rather than authoritative.
    @Test("a version file already at the destination is not overwritten by the old one")
    func destinationVersionFileIsAuthoritative() throws {
        let location = try makeLocation()
        let legacy = location.legacyFiles(owner: owner)
        let current = location.files(owner: owner)
        try seedStore(at: legacy.database, value: "row")
        try Database.setUserVersion(version: 3, files: current)
        try Database.setUserVersion(version: 1, files: legacy)

        _ = StoreMigration.migrateIfNeeded(owner: owner, location: location)

        #expect(try Database.userVersion(files: current) == 3)
        #expect(!exists(legacy.version))
    }

    // MARK: - Failing -

    @Test("an unreadable legacy store fails without leaving a partial one behind")
    func corruptLegacyStoreDegrades() throws {
        let location = try makeLocation()
        let legacy = location.legacyFiles(owner: owner)
        let current = location.files(owner: owner)
        try Data("not a database".utf8).write(to: legacy.database)
        try Database.setUserVersion(version: 5, files: legacy)

        let outcome = StoreMigration.migrateIfNeeded(owner: owner, location: location)

        guard case .failed = outcome else {
            Issue.record("expected a failure, got \(outcome)")
            return
        }

        // Nothing at the destination, so login opens a fresh store rather than one that is
        // half of something else.
        #expect(!exists(current.database))
        #expect(!exists(current.version))
    }
}

