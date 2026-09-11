//
//  ExtensionStore.swift
//  FlipcashStore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore
import SQLite
// For `SQLITE_BUSY`. SQLite.swift re-exports the connection API but not the result codes.
import SQLite3

nonisolated private let logger = Logger(label: "flipcash.database.extension")

/// A bounded open-write-close cycle over the shared store, for callers that are not the app.
///
/// The app opens the store once at login and keeps it open. An extension cannot: it is woken for a
/// few seconds and then suspended, and a process suspended while holding a lock on App Group storage
/// is the case iOS terminates with `0xdead10cc`. So every write from outside the app opens the store,
/// writes, checkpoints, and closes within one call.
///
/// The two guards in front of that cycle matter more than the cycle itself, and neither is a
/// nicety — see ``perform(owner:location:fileManager:schemaVersion:_:)``.
nonisolated public enum ExtensionStore {

    public enum Outcome: Equatable {
        /// The body ran and the store was checkpointed and closed.
        case wrote
        /// No store at the shared location. Nothing was created.
        case noStore
        /// The version recorded beside the store is not the one this build writes.
        case versionMismatch(recorded: Int?)
        /// Another process held the write lock for longer than the busy timeout.
        case busy
        case failed(String)
    }

    /// Opens the owner's store, runs `body` against it, then checkpoints and closes.
    ///
    /// Returns rather than throws. Every outcome here is one the caller answers by doing nothing —
    /// a notification extension has no way to surface a store problem to the user, and no reason to
    /// fail delivery over one.
    ///
    /// **This never creates a store.** `Database.init` would happily create one, and an empty store
    /// appearing at the shared path before the app has migrated is data loss, not an inconvenience:
    /// `StoreMigration` reads an existing destination as a finished migration and deletes the legacy
    /// store, so the user's history would go with it. The existence check is what prevents that.
    ///
    /// **It also never writes into a schema it does not match.** A recorded version lower than
    /// ``Database/schemaVersion`` means the app has not yet rebuilt the store for this build, and a
    /// higher one means a newer build wrote it and the user has since downgraded. Rebuilding belongs
    /// to the app, so both cases no-op.
    @discardableResult
    public static func perform(
        owner: PublicKey,
        location: StoreLocation = .resolved(),
        fileManager: FileManager = .default,
        schemaVersion: Int = Database.schemaVersion,
        _ body: (Database) throws -> Void
    ) -> Outcome {
        let files = location.files(owner: owner)

        guard fileManager.fileExists(atPath: files.database.path) else {
            return .noStore
        }

        let recorded = try? Database.userVersion(files: files)
        guard recorded == schemaVersion else {
            return .versionMismatch(recorded: recorded)
        }

        do {
            let database = try Database(url: files.database)
            // Checkpoints and drops both connections. Runs even when `body` throws: a store left
            // open is the thing this type exists to avoid.
            defer { try? database.close() }
            try body(database)
            return .wrote

        } catch let error as SQLite.Result where error.isBusy {
            // The app holds the write lock. Giving up is correct — whatever this write was carrying,
            // the app is in a better position to fetch it than the extension is to wait for it.
            return .busy

        } catch {
            logger.error("Extension store write failed", metadata: ["error": "\(error)"])
            return .failed("\(error)")
        }
    }
}

extension SQLite.Result {

    /// Whether this is `SQLITE_BUSY`, under either the primary or an extended result code.
    ///
    /// Extended codes carry the primary code in their low byte, so one mask covers both shapes.
    var isBusy: Bool {
        let code: Int32 = switch self {
        case .error(_, let code, _): code
        case .extendedError(_, let extendedCode, _): extendedCode
        }
        return code & 0xFF == SQLITE_BUSY
    }
}
