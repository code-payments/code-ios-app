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
}
