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
        try writer.run("PRAGMA journal_mode = WAL")
        try writer.run("PRAGMA cache_size = 10000")
        
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

extension Database {
    private func createTablesIfNeeded() throws {
        let roomTable    = RoomTable()
        let messageTable = MessageTable()
        let memberTable  = MemberTable()
        let userTable    = UserTable()
        let pointerTable = PointerTable()
        
        try writer.transaction {
            try writer.run(roomTable.table.create(ifNotExists: true, withoutRowid: true) { t in
                t.column(roomTable.serverID, primaryKey: true)
                t.column(roomTable.kind)
                t.column(roomTable.title)
                t.column(roomTable.roomNumber, unique: true)
                t.column(roomTable.ownerUserID)
                t.column(roomTable.coverQuarks, defaultValue: 0)
                t.column(roomTable.unreadCount, defaultValue: 0)
                t.column(roomTable.isDeleted, defaultValue: false)
            })
            
            try writer.run(messageTable.table.create(ifNotExists: true, withoutRowid: true) { t in
                t.column(messageTable.serverID, primaryKey: true)
                t.column(messageTable.roomID) // FK room.serverID
                t.column(messageTable.date)
                t.column(messageTable.state, defaultValue: 0) // Default: .sent
                t.column(messageTable.senderID)
                t.column(messageTable.contents)
                t.column(messageTable.isBatch, defaultValue: false)
                
                t.foreignKey(messageTable.roomID, references: roomTable.table, roomTable.serverID, delete: .cascade)
            })
            
            try writer.run(memberTable.table.create(ifNotExists: true, withoutRowid: true) { t in
                t.column(memberTable.userID) // FK user.serverID
                t.column(memberTable.roomID) // FK room.serverID
                t.column(memberTable.isMuted)
                
                t.primaryKey(memberTable.userID, memberTable.roomID)
                t.foreignKey(memberTable.roomID, references: userTable.table, userTable.serverID, delete: .setNull)
                t.foreignKey(memberTable.roomID, references: roomTable.table, roomTable.serverID, delete: .cascade)
            })
            
            try writer.run(userTable.table.create(ifNotExists: true, withoutRowid: true) { t in
                t.column(userTable.serverID, primaryKey: true)
                t.column(userTable.displayName)
                t.column(userTable.avatarURL)
            })
            
            try writer.run(pointerTable.table.create(ifNotExists: true, withoutRowid: true) { t in
                t.column(pointerTable.userID)    // FK user.serverID
                t.column(pointerTable.roomID)    // FK room.serverID
                t.column(pointerTable.kind)
                t.column(pointerTable.messageID)
                
                t.primaryKey(pointerTable.userID, pointerTable.roomID)
                t.foreignKey(pointerTable.roomID, references: roomTable.table, roomTable.serverID, delete: .cascade)
                t.foreignKey(pointerTable.userID, references: userTable.table, memberTable.userID, delete: .cascade)
            })
        }
    }
}
