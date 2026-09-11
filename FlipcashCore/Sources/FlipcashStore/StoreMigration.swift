//
//  StoreMigration.swift
//  Code
//

import Foundation
import FlipcashCore
import SQLite

nonisolated private let logger = Logger(label: "flipcash.database.migration")

/// Moves an existing store out of the app's private Application Support directory and into the App
/// Group container, once, on the first launch of a build that knows about the shared location.
///
/// Two properties matter more than speed here. It has to survive being interrupted partway through —
/// the process can be killed between any two file operations — and it has to survive a user who
/// never launches the old build again, which is why nothing is left behind for a later pass to
/// finish.
nonisolated public enum StoreMigration {

    public enum Outcome: Equatable {
        /// Nothing to do: no store in either location, or the two locations are the same directory.
        case notNeeded
        /// A store was already at the shared location. Any legacy remnants were swept.
        case alreadyMigrated
        /// A legacy store was checkpointed and moved.
        case migrated
        /// The move failed. Anything this migration had put at the destination was removed, so the
        /// caller opens a fresh store rather than a half-moved one.
        case failed(String)
    }

    /// Migrates the owner's store into `location.directory` if it is not already there.
    ///
    /// Never throws. A migration that cannot complete degrades to a fresh store, which the app
    /// re-syncs; throwing here would instead block login on a file-system problem.
    public static func migrateIfNeeded(
        owner: PublicKey,
        location: StoreLocation,
        fileManager: FileManager = .default
    ) -> Outcome {
        let legacy = location.legacyFiles(owner: owner)
        let current = location.files(owner: owner)

        // The App Group container was unavailable, so `resolved` fell back and both sides name the
        // same paths. Moving a file onto itself fails; there is also nothing to move.
        guard current.database != legacy.database else {
            return .notNeeded
        }

        let destinationExists = fileManager.fileExists(atPath: current.database.path)
        let legacyExists = fileManager.fileExists(atPath: legacy.database.path)

        guard destinationExists || legacyExists else {
            return .notNeeded
        }

        do {
            if destinationExists {
                // Either a finished migration or one that stopped after the database landed. The
                // destination store is authoritative either way; the legacy copy is stale from the
                // moment the first write goes to the new one, so it is removed rather than merged.
                try adoptVersionFile(from: legacy, to: current, fileManager: fileManager)
                sweep(legacy, fileManager: fileManager)
                return .alreadyMigrated
            }

            // Fold the write-ahead log into the main database file first. After this the store is a
            // single file, which is the only shape that survives a half-completed move: moving a
            // database and its `-wal` as two operations can leave the pair split across directories,
            // and SQLite reads that as a database with no log rather than as an error.
            try checkpoint(at: legacy.database)

            // The version file moves before the database, and the order is the resumable one. If the
            // process dies between the two, the next launch sees no database at the destination,
            // retries, and finds the version file already there — which `adoptVersionFile` treats as
            // done. Moving the database first would instead leave a store at the destination with no
            // recorded schema version, which reads as version 0 and triggers a full rebuild.
            try adoptVersionFile(from: legacy, to: current, fileManager: fileManager)
            try fileManager.moveItem(at: legacy.database, to: current.database)

            sweep(legacy, fileManager: fileManager)
            return .migrated

        } catch {
            // Only remove what this migration could have created. When the destination store already
            // existed on entry it holds real data, and clearing it would be the migration destroying
            // the thing it was meant to preserve.
            if !destinationExists {
                discard(current, fileManager: fileManager)
            }

            logger.error(
                "Store migration failed",
                metadata: ["error": "\(error)", "destinationExisted": "\(destinationExists)"]
            )
            return .failed("\(error)")
        }
    }

    // MARK: - Steps -

    /// Runs a truncating checkpoint against the legacy store and closes it again.
    ///
    /// The connection is scoped to this function on purpose: SQLite.swift releases its handle from
    /// `deinit`, so the store is only closed — and therefore only safe to move — once this returns.
    private static func checkpoint(at url: URL) throws {
        let connection = try Connection(url.path)
        connection.busyTimeout = 2
        try connection.run("PRAGMA wal_checkpoint(TRUNCATE);")
    }

    /// Moves the version file to the destination, tolerating a source that is already gone.
    ///
    /// A missing destination version reads as version 0, which makes the app delete the store it
    /// just migrated and rebuild it — so this is not best-effort, unlike the `-wal`/`-shm` sweep.
    private static func adoptVersionFile(
        from legacy: StoreLocation.Files,
        to current: StoreLocation.Files,
        fileManager: FileManager
    ) throws {
        guard !fileManager.fileExists(atPath: current.version.path) else {
            // Already moved, by this migration's earlier interrupted run.
            return
        }
        guard fileManager.fileExists(atPath: legacy.version.path) else {
            // No recorded version anywhere. The caller's version check writes one.
            return
        }
        try fileManager.moveItem(at: legacy.version, to: current.version)
    }

    /// Removes what the legacy location has left over. Best-effort by design: the store has already
    /// moved, so a file that cannot be deleted costs disk space rather than correctness.
    ///
    /// The `-wal` and `-shm` are not moved. The checkpoint folded the log into the database, and
    /// `-shm` is scratch that SQLite rebuilds, so carrying either across would only risk pairing a
    /// stale log with a migrated database.
    private static func sweep(_ legacy: StoreLocation.Files, fileManager: FileManager) {
        for url in [legacy.database, legacy.wal, legacy.shm, legacy.version] {
            try? fileManager.removeItem(at: url)
        }
    }

    private static func discard(_ current: StoreLocation.Files, fileManager: FileManager) {
        for url in [current.database, current.wal, current.shm, current.version] {
            try? fileManager.removeItem(at: url)
        }
    }
}
