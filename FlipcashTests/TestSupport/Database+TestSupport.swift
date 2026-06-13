//
//  Database+TestSupport.swift
//  FlipcashTests
//

import Foundation
@testable import Flipcash

extension Database {
    /// Build a fresh SQLite-backed `Database` rooted in `NSTemporaryDirectory()`
    /// with a unique filename. Callers are responsible for calling
    /// ``removeTemp(at:)`` in a `defer` to clean up the `.sqlite` / `-wal` /
    /// `-shm` files; the database also removes them when deallocated.
    static func makeTemp() throws -> (database: Database, url: URL) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("test-\(UUID().uuidString).sqlite")
        return (try TempDatabase(tempURL: url), url)
    }

    /// Removes the temp database file and its SQLite WAL/SHM sidecars.
    static func removeTemp(at url: URL) {
        let manager = FileManager.default
        let paths: [URL] = [
            url,
            URL(fileURLWithPath: url.path + "-wal"),
            URL(fileURLWithPath: url.path + "-shm"),
        ]
        for path in paths where manager.fileExists(atPath: path.path) {
            try? manager.removeItem(at: path)
        }
    }
}

/// Temp database that removes its on-disk files when deallocated, covering
/// callers that cannot scope a `defer` around the database's lifetime.
nonisolated private final class TempDatabase: Database {

    private let url: URL

    init(tempURL: URL) throws {
        self.url = tempURL
        try super.init(url: tempURL)
    }

    deinit {
        Database.removeTemp(at: url)
    }
}
