//
//  Database.swift
//  Code
//
//  Created by Dima Bart on 2025-04-11.
//

import Foundation
import FlipcashCore
public import SQLite

nonisolated private let logger = Logger(label: "flipcash.database")

public typealias Expression = SQLite.Expression

// SQLite.swift serializes reads/writes through each `Connection`'s own
// dispatch queue, so concurrent calls into `reader` and `writer` are safe
// despite Database itself being a reference type. Marking it
// `@unchecked Sendable` lets background write paths (e.g. RatesController's
// rate persistence queue) capture it without escaping Swift 6 isolation.
// The connections themselves are mutable now that they can be closed and
// reopened, so `lock` — not isolation — is what makes that state safe.
// FOLLOW-UP: Remove @unchecked when SQLite.swift declares Connection: Sendable.
// `open` rather than `public` so the test bundle can subclass it to tie temp-file cleanup to the
// database's lifetime. Every member stays `public`, so a subclass can add state but cannot override
// any behaviour.
nonisolated open class Database: @unchecked Sendable {

    private let storeURL: URL

    /// Both are `nil` while the store is closed, and are guarded by `lock` — the two
    /// accessors below are the only things that touch them.
    private var _reader: Connection?
    private var _writer: Connection?

    private let lock = NSLock()

    /// The write connection, opening the store first if it is currently closed.
    public var writer: Connection {
        get throws {
            lock.lock()
            defer { lock.unlock() }

            if let existing = _writer {
                return existing
            }

            let connection = try Self.openWriter(at: storeURL)
            _writer = connection
            return connection
        }
    }

    /// The read connection, opening the store first if it is currently closed.
    public var reader: Connection {
        get throws {
            lock.lock()
            defer { lock.unlock() }

            if let existing = _reader {
                return existing
            }

            let connection = try Self.openReader(at: storeURL)
            _reader = connection
            return connection
        }
    }
    
    // MARK: - Init -
    
    public init(url: URL) throws {
        self.storeURL = url

        // Opening both here keeps an unusable store path failing at `init`, where it
        // has always failed, rather than deferring it to whichever query runs first.
        _ = try writer
        _ = try reader

        try createTablesIfNeeded()
    }

    private static func openWriter(at url: URL) throws -> Connection {
        let connection = try Connection(url.path)

        // Seconds, not milliseconds: SQLite.swift multiplies by 1000 before handing
        // the value to `sqlite3_busy_timeout`.
        connection.busyTimeout = 2

        // `journal_mode` is persisted in the database header, but the other two are
        // per-connection and have to be set again every time the store is reopened.
        try connection.run("PRAGMA journal_mode = WAL;")
        try connection.run("PRAGMA cache_size = 10000;")
        try connection.run("PRAGMA foreign_keys = ON;")

        return connection
    }

    private static func openReader(at url: URL) throws -> Connection {
        let connection = try Connection(url.path, readonly: true)
        connection.busyTimeout = 2
        return connection
    }
    
    // MARK: - Transaction -
    
    /// Always inline this function to ensure that captureError
    /// captures the function in which this was called, otherwise
    /// it will always captured in transaction {}
    @inline(__always)
    public func transaction(silent: Bool = false, _ block: (Database) throws -> Void) rethrows {
        do {
            let connection = try writer
            let startChangeCount = connection.totalChanges
            // IMMEDIATE: callers read and write inside the block; see replaceConversationFeed.
            try connection.transaction(.immediate) { [unowned self] in
                try block(self)
            }
            let endChangeCount = connection.totalChanges
            
            // There are instances where we want to commit
            // the transaction but avoid notifying the UI
            // layer of the change. Also, we'll check if
            // there's been any changes in this transaction
            // to avoid reloading unnecessarily.
            if !silent {
                let changeDelta = endChangeCount - startChangeCount
                if changeDelta > 0 {
                    NotificationQueue.default.enqueue(
                        .init(
                            name: .databaseDidChange,
                            userInfo: [
                                "changeCount": changeDelta,
                            ]
                        ),
                        postingStyle: .asap,
                        coalesceMask: .onName,
                        forModes: [.common]
                    )
                }
            }
            
        } catch {
            logger.error("Transaction error", metadata: ["error": "\(error)"])
        }
    }
    
    // MARK: - Lifecycle -

    private static let checkpointPragma = "PRAGMA wal_checkpoint(TRUNCATE);"

    /// Flushes the write-ahead log back into the main database file and truncates it.
    ///
    /// TRUNCATE rather than PASSIVE: a passive checkpoint gives up silently when any
    /// reader is mid-transaction, which is the case that leaves the WAL growing without
    /// bound. This blocks up to `busyTimeout` instead, and throws when it cannot finish.
    public func checkpoint() throws {
        try writer.run(Self.checkpointPragma)
    }

    /// Checkpoints the write-ahead log and drops both connections.
    ///
    /// Dropping the references is what closes the store: SQLite.swift's `Connection`
    /// releases its handle from `deinit` and exposes no `close()` of its own. So a
    /// connection someone else still holds — a caller partway through `transaction(_:)`,
    /// say — closes when that caller returns rather than here.
    ///
    /// Nothing pairs with this. The next `reader` or `writer` access reopens the store
    /// and reapplies the pragmas, which is what lets a close arriving at an awkward
    /// moment heal itself instead of leaving the caller with a dead object.
    public func close() throws {
        lock.lock()
        defer {
            _reader = nil
            _writer = nil
            lock.unlock()
        }

        // Checkpoint before the writer goes. A WAL left on disk is replayed by whichever
        // process opens the store next, which is correct but makes that open cost time
        // proportional to the log rather than to what the caller wanted to read.
        try _writer?.run(Self.checkpointPragma)
    }

    // MARK: - Versioning -

    /// The schema version this build writes.
    ///
    /// A launch that finds a lower version recorded beside the store deletes the store and rebuilds
    /// it from sync, which is the project's substitute for schema migrations. Bump this whenever a
    /// table definition in `Schema.swift` changes.
    ///
    /// This used to be the `SQLiteVersion` key in the app's `Info.plist`. It moved into code because
    /// the notification service extension needs the same number to decide whether the store on disk
    /// is one it understands, and an extension cannot read the app's `Info.plist` — separate bundles.
    /// Both targets link this module, so they cannot disagree.
    public static let schemaVersion = 35

    /// Removes the store and the write-ahead log files beside it.
    ///
    /// The version file is deliberately left alone: the caller deletes the store because the
    /// recorded version is stale, and writes the new one immediately afterwards.
    public static func deleteStore(files: StoreLocation.Files) throws {
        let urlsToRemove: [URL] = [
            files.database,
            files.shm,
            files.wal,
        ]
        
        try urlsToRemove.forEach {
            if FileManager.default.fileExists(atPath: $0.path) {
                try FileManager.default.removeItem(at: $0)
            }
        }
    }
    
    public static func setUserVersion(version: Int, files: StoreLocation.Files) throws {
        try "\(version)".write(
            to: files.version,
            atomically: true,
            encoding: .utf8
        )
    }
    
    public static func userVersion(files: StoreLocation.Files) throws -> Int? {
        let versionString = try String(
            contentsOf: files.version,
            encoding: .utf8
        )
        
        return Int(versionString.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

nonisolated extension Notification.Name {
    public static let databaseDidChange = Notification.Name("databaseDidChange")
}

