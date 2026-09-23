//
//  Regression_6ab3f91758142669ea6cc93f.swift
//  FlipcashTests
//
//  "Notification store write failed": failed("locking protocol (code: 15)") from the
//  NotificationService extension. SQLite returns SQLITE_PROTOCOL when a connection loses the WAL
//  read-lock race 100 times (about 10 s of backoff that busy_timeout does not cap). That is
//  contention, but ExtensionStore only recognised SQLITE_BUSY, so it came back as `.failed` and
//  was reported.
//
//  Fix: ExtensionStore treats SQLITE_PROTOCOL as contention, so it returns `.busy`.
//
//  The error is thrown directly because provoking a real one takes a 10 s lost race.
//

import Foundation
import Testing
import SQLite
import SQLite3
import FlipcashCore
import FlipcashStore
@testable import Flipcash

@Suite("Regression: 6ab3f91 – SQLITE_PROTOCOL reported as a failed store write", .bug("6ab3f91758142669ea6cc93f"))
struct Regression_6ab3f91 {

    private let owner = try! PublicKey(Data(repeating: 7, count: 32))

    /// A seeded store at a throwaway location, as a logged-in app leaves it.
    private func makeSeededLocation() throws -> StoreLocation {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("regression-6ab3f91-\(UUID().uuidString)")
        let group = root.appendingPathComponent("group")
        let support = root.appendingPathComponent("support")
        try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let location = StoreLocation(directory: group, legacyDirectory: support, isShared: true)

        let files = location.files(owner: owner)
        let database = try Database(url: files.database)
        try database.close()
        try Database.setUserVersion(version: Database.schemaVersion, files: files)
        return location
    }

    @Test("a lost WAL lock race ends the cycle as busy, not as a failure")
    func lockingProtocol_isBusy() throws {
        let location = try makeSeededLocation()

        let outcome = ExtensionStore.perform(owner: owner, location: location) { _ in
            throw SQLite.Result.error(message: "locking protocol", code: SQLITE_PROTOCOL, statement: nil)
        }

        #expect(outcome == .busy)
    }

    @Test("other SQLite errors are still failures")
    func corrupt_isFailed() throws {
        let location = try makeSeededLocation()

        let outcome = ExtensionStore.perform(owner: owner, location: location) { _ in
            throw SQLite.Result.error(message: "database disk image is malformed", code: SQLITE_CORRUPT, statement: nil)
        }

        guard case .failed = outcome else {
            Issue.record("expected a failure, got \(outcome)")
            return
        }
    }
}
