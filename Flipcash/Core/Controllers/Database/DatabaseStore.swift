//
//  DatabaseStore.swift
//  Flipcash
//

import Foundation
import FlipcashCore

private let logger = Logger(label: "flipcash.database-store")

/// Opens one `Database` per owner and returns that same instance on every later request,
/// so repeat logins in one process share a single SQLite writer instead of contending for the file.
final class DatabaseStore {

    private var databases: [PublicKey: Database] = [:]

    /// The owner's `Database`, opened (and rebuilt if its on-disk version is outdated) on first use.
    func database(for owner: PublicKey) throws -> Database {
        if let database = databases[owner] {
            return database
        }

        try createApplicationSupportIfNeeded()

        // Currently we don't do migrations so every time
        // the user version is outdated, we'll rebuild the
        // database during sync.
        let userVersion = (try? Database.userVersion(owner: owner)) ?? 0
        let currentVersion = try InfoPlist.value(for: "SQLiteVersion").integer()
        if currentVersion > userVersion {
            try Database.deleteStore(owner: owner)
            logger.error("Outdated user version, deleted database.")
            try Database.setUserVersion(version: currentVersion, owner: owner)
        }

        let database = try Database(url: .dataStore(owner: owner))
        databases[owner] = database
        return database
    }

    private func createApplicationSupportIfNeeded() throws {
        if !FileManager.default.fileExists(atPath: URL.applicationSupportDirectory.path) {
            try FileManager.default.createDirectory(
                at: .applicationSupportDirectory,
                withIntermediateDirectories: false
            )
        }
    }
}
