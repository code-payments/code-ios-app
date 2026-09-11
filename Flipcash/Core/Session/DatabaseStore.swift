//
//  DatabaseStore.swift
//  Flipcash
//

import Foundation
import FlipcashCore
import FlipcashStore

private let logger = Logger(label: "flipcash.database-store")

/// Opens one ``Database`` per owner and hands back that same instance on every later request.
///
/// `SessionAuthenticator` builds a fresh `SessionContainer` on each login, and a logout that is
/// followed by a login in the same process used to open a second `Database` on the same file. Both
/// stayed alive — the old session's controllers hold their `Database` until they are released — so
/// two connections competed for the write lock and the loser reported SQLITE_BUSY (Bugsnag
/// 6a4fde3). Caching by owner means the second login reuses the first connection instead.
///
/// Entries are never evicted. One `Database` per account per process is bounded by how many
/// accounts a person signs into before backgrounding the app, and dropping an entry would
/// reintroduce exactly the second connection this exists to prevent.
final class DatabaseStore {

    private var databases: [PublicKey: Database] = [:]

    /// The owner's `Database`, opened on first use: resolves the store location, migrates a legacy
    /// store into the App Group container, and rebuilds the file when its schema is outdated.
    func database(for owner: PublicKey) throws -> Database {
        if let database = databases[owner] {
            return database
        }

        // Resolved once. Two calls could in principle disagree — the container lookup is a
        // system call, not a constant — and a migration that reads one directory while the
        // store opens from another is the failure this avoids.
        let location = StoreLocation.resolved()
        let files = location.files(owner: owner)

        if !location.isShared {
            // The store still works; the notification extension cannot see it, so anything the
            // extension prefetches is invisible to the app until this is fixed. That is an
            // entitlement or provisioning problem, and it is silent without this.
            ErrorReporting.captureError(
                StoreError.appGroupUnavailable,
                reason: "App Group container unavailable, database fell back to Application Support"
            )
        }

        try createStoreDirectoryIfNeeded(at: location.directory)

        switch StoreMigration.migrateIfNeeded(owner: owner, location: location) {
        case .notNeeded, .alreadyMigrated:
            break
        case .migrated:
            logger.info("Migrated the database into the App Group container.")
        case .failed(let description):
            // The migration cleaned up after itself, so what follows opens a fresh store and
            // sync repopulates it. Worth reporting because the user pays for it in a full
            // re-sync, and because it means the legacy store is still on disk.
            ErrorReporting.captureError(
                StoreError.migrationFailed(description),
                reason: "Database migration to the App Group container failed"
            )
        }

        // Currently we don't do migrations so every time
        // the user version is outdated, we'll rebuild the
        // database during sync.
        let userVersion = (try? Database.userVersion(files: files)) ?? 0
        let currentVersion = Database.schemaVersion
        if currentVersion > userVersion {
            try Database.deleteStore(files: files)
            logger.error("Outdated user version, deleted database.")
            try Database.setUserVersion(version: currentVersion, files: files)
        }

        let database = try Database(url: files.database)
        databases[owner] = database
        return database
    }

    /// Creates the store's directory when it is missing.
    ///
    /// `withIntermediateDirectories: true` where the old Application Support version passed
    /// `false`: the App Group container root already exists once it resolves, so the call is
    /// usually a no-op, and `true` also makes it succeed rather than throw in that case.
    private func createStoreDirectoryIfNeeded(at directory: URL) throws {
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
    }

    private enum StoreError: Error {
        case appGroupUnavailable
        case migrationFailed(String)
    }
}
