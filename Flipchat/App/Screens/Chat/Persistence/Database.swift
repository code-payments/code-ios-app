//
//  Database.swift
//  Code
//
//  Created by Dima Bart on 2024-11-30.
//

import Foundation
import FlipchatServices
import SQLite

typealias Expression = SQLite.Expression

@MainActor
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
    
    static func deleteStore(for userID: UserID) throws {
        let url = URL.store(for: userID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
            try FileManager.default.removeItem(at: .storeSHM(for: userID))
            try FileManager.default.removeItem(at: .storeWAL(for: userID))
        }
    }
    
    static func setUserVersion(version: Int, userID: UserID) throws {
        try "\(version)".write(
            to: .versionFile(for: userID),
            atomically: true,
            encoding: .utf8
        )
    }
    
    static func userVersion(userID: UserID) throws -> Int? {
        let versionString = try String(
            contentsOf: .versionFile(for: userID),
            encoding: .utf8
        )
        
        return Int(versionString.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

extension URL {
    static func store(for userID: UserID) -> URL {
        URL.applicationSupportDirectory.appendingPathComponent("\(userID.uuid.uuidString).sqlite")
    }
    
    static func storeWAL(for userID: UserID) -> URL {
        URL.applicationSupportDirectory.appendingPathComponent("\(userID.uuid.uuidString).sqlite-wal")
    }
    
    static func storeSHM(for userID: UserID) -> URL {
        URL.applicationSupportDirectory.appendingPathComponent("\(userID.uuid.uuidString).sqlite-shm")
    }
    
    static func versionFile(for userID: UserID) -> URL {
        URL.applicationSupportDirectory.appendingPathComponent("\(userID.uuid.uuidString).version")
    }
}
