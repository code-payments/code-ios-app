//
//  DatabaseLifecycleTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import Flipcash

@Suite("Database lifecycle")
struct DatabaseLifecycleTests {

    /// A store in a fresh temporary directory, plus the URL of its write-ahead log.
    private func makeDatabase() throws -> (database: Database, walURL: URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("db-\(UUID().uuidString).sqlite")
        return (try Database(url: url), URL(fileURLWithPath: url.path + "-wal"))
    }

    private func size(of url: URL) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? Int) ?? 0
    }

    @Test("a checkpoint empties the write-ahead log")
    func checkpointEmptiesWAL() throws {
        let (database, walURL) = try makeDatabase()
        try database.writer.run("CREATE TABLE probe (id INTEGER PRIMARY KEY, value TEXT);")
        for index in 0..<200 {
            try database.writer.run("INSERT INTO probe (value) VALUES (?);", "row-\(index)")
        }

        // A non-empty WAL is also the check that `journal_mode = WAL` took effect at init;
        // in any other journal mode there would be no `-wal` file to measure.
        #expect(size(of: walURL) > 0)

        try database.checkpoint()

        #expect(size(of: walURL) == 0)
    }

    @Test("data written before a checkpoint survives it")
    func checkpointPreservesData() throws {
        let (database, _) = try makeDatabase()
        try database.writer.run("CREATE TABLE probe (id INTEGER PRIMARY KEY, value TEXT);")
        try database.writer.run("INSERT INTO probe (value) VALUES (?);", "kept")

        try database.checkpoint()

        let value = try database.reader.scalar("SELECT value FROM probe LIMIT 1;") as? String
        #expect(value == "kept")
    }

    @Test("checkpointing an untouched store is not an error")
    func checkpointWithNothingToFlush() throws {
        let (database, walURL) = try makeDatabase()

        try database.checkpoint()

        #expect(size(of: walURL) == 0)
    }

    @Test("closing checkpoints the write-ahead log")
    func closeEmptiesWAL() throws {
        let (database, walURL) = try makeDatabase()
        try database.writer.run("CREATE TABLE probe (id INTEGER PRIMARY KEY, value TEXT);")
        for index in 0..<200 {
            try database.writer.run("INSERT INTO probe (value) VALUES (?);", "row-\(index)")
        }
        #expect(size(of: walURL) > 0)

        try database.close()

        #expect(size(of: walURL) == 0)
    }

    @Test("a read after a close reopens the store with its rows intact")
    func readAfterCloseReopens() throws {
        let (database, _) = try makeDatabase()
        try database.writer.run("CREATE TABLE probe (id INTEGER PRIMARY KEY, value TEXT);")
        try database.writer.run("INSERT INTO probe (value) VALUES (?);", "kept")

        try database.close()

        let value = try database.reader.scalar("SELECT value FROM probe LIMIT 1;") as? String
        #expect(value == "kept")
    }

    @Test("a write after a close lands, and survives a second close")
    func writeAfterCloseSurvivesAnotherCycle() throws {
        let (database, _) = try makeDatabase()
        try database.writer.run("CREATE TABLE probe (id INTEGER PRIMARY KEY, value TEXT);")

        try database.close()
        try database.writer.run("INSERT INTO probe (value) VALUES (?);", "after-close")
        try database.close()

        let value = try database.reader.scalar("SELECT value FROM probe LIMIT 1;") as? String
        #expect(value == "after-close")
    }

    @Test("a transaction after a close reopens and commits")
    func transactionAfterCloseCommits() throws {
        let (database, _) = try makeDatabase()
        try database.writer.run("CREATE TABLE probe (id INTEGER PRIMARY KEY, value TEXT);")

        try database.close()
        try database.transaction(silent: true) { db in
            try db.writer.run("INSERT INTO probe (value) VALUES (?);", "committed")
        }

        let value = try database.reader.scalar("SELECT value FROM probe LIMIT 1;") as? String
        #expect(value == "committed")
    }

    @Test("the per-connection pragmas are reapplied when the store reopens")
    func pragmasAreReappliedOnReopen() throws {
        let (database, _) = try makeDatabase()

        try database.close()

        let writer = try database.writer
        #expect(try writer.scalar("PRAGMA foreign_keys;") as? Int64 == 1)
        #expect(try writer.scalar("PRAGMA cache_size;") as? Int64 == 10_000)
        #expect(try writer.scalar("PRAGMA journal_mode;") as? String == "wal")
    }

    /// `PRAGMA busy_timeout` reports milliseconds; SQLite.swift's `busyTimeout` property
    /// is in seconds and multiplies by 1000 on the way to `sqlite3_busy_timeout`. This is
    /// the assertion that catches the two being confused.
    @Test("both connections wait two seconds on a busy store, before and after a reopen")
    func busyTimeoutIsTwoSeconds() throws {
        let (database, _) = try makeDatabase()

        #expect(try database.writer.scalar("PRAGMA busy_timeout;") as? Int64 == 2_000)
        #expect(try database.reader.scalar("PRAGMA busy_timeout;") as? Int64 == 2_000)

        try database.close()

        #expect(try database.writer.scalar("PRAGMA busy_timeout;") as? Int64 == 2_000)
        #expect(try database.reader.scalar("PRAGMA busy_timeout;") as? Int64 == 2_000)
    }

    @Test("closing twice is not an error")
    func closeIsIdempotent() throws {
        let (database, _) = try makeDatabase()

        try database.close()
        try database.close()

        #expect(try database.reader.scalar("SELECT 1;") as? Int64 == 1)
    }
}
