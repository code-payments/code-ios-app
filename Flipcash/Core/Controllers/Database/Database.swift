//
//  Database.swift
//  Code
//
//  Created by Dima Bart on 2025-04-11.
//

import Foundation
import FlipcashCore
import SQLite

typealias Expression = SQLite.Expression

class Database {
    
    let reader: Connection
    let writer: Connection
    
    var commit: (() -> Void)?
    
    private let storeURL: URL
    
    // MARK: - Init -
    
    init(url: URL) throws {
        self.storeURL = url
        
        self.writer = try Connection(url.path)
        
        writer.busyTimeout = 2000 // 2 sec
        try writer.run("PRAGMA journal_mode = WAL;")
        try writer.run("PRAGMA cache_size = 10000;")
        try writer.run("PRAGMA foreign_keys = ON;")
        
        self.reader = try Connection(url.path, readonly: true)
        reader.busyTimeout = 2000 // 2 Sec
        
        try createTablesIfNeeded()
        
//        writer.trace { sql in
//            print("[WRITER]: \(sql)")
//        }
//
//        reader.trace { sql in
//            print("[READER]: \(sql)")
//        }
    }
    
    // MARK: - Transaction -
    
    /// Always inline this function to ensure that captureError
    /// captures the function in which this was called, otherwise
    /// it will always captured in transaction {}
    @inline(__always)
    func transaction(silent: Bool = false, _ block: (Database) throws -> Void) throws {
//        let start = Date.now
        do {
            let startChangeCount = writer.totalChanges
            try writer.transaction { [unowned self] in
                try block(self)
            }
            let endChangeCount = writer.totalChanges
            
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
                    commit?()
                } else {
                    print("Transaction detected no changes. Skipping commit...")
                }
            }
            
        } catch {
            trace(.failure, components: "Transaction error: \(error)")
//            ErrorReporting.captureError(error)
        }
//        print("[DB TX]: \(Date.now.timeIntervalSince1970 - start.timeIntervalSince1970) seconds")
    }
    
    // MARK: - Versioning -
    
    static func deleteStore(owner: PublicKey) throws {
        let urlsToRemove: [URL] = [
            .dataStore(owner: owner),
            .storeSHM(owner: owner),
            .storeWAL(owner: owner),
        ]
        
        try urlsToRemove.forEach {
            if FileManager.default.fileExists(atPath: $0.path) {
                try FileManager.default.removeItem(at: $0)
            }
        }
    }
    
    static func setUserVersion(version: Int, owner: PublicKey) throws {
        try! "\(version)".write(
            to: .versionFile(owner: owner),
            atomically: true,
            encoding: .utf8
        )
    }
    
    static func userVersion(owner: PublicKey) throws -> Int? {
        let versionString = try String(
            contentsOf: .versionFile(owner: owner),
            encoding: .utf8
        )
        
        return Int(versionString.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

extension URL {
    static func dataStore(owner: PublicKey) -> URL {
        URL.applicationSupportDirectory.appendingPathComponent("flipcash-\(owner.base58).sqlite")
    }
    
    static func storeWAL(owner: PublicKey) -> URL {
        URL.applicationSupportDirectory.appendingPathComponent("flipcash-\(owner.base58).sqlite-wal")
    }
    
    static func storeSHM(owner: PublicKey) -> URL {
        URL.applicationSupportDirectory.appendingPathComponent("flipcash-\(owner.base58).sqlite-shm")
    }
    
    static func versionFile(owner: PublicKey) -> URL {
        URL.applicationSupportDirectory.appendingPathComponent("flipcash-\(owner.base58)version")
    }
}

extension Notification.Name {
    static let databaseDidChange = Notification.Name("databaseDidChange")
}

extension Database {
    static let mock = try! Database(url: .temporaryDirectory.appendingPathComponent("mock.sqlite"))
}
