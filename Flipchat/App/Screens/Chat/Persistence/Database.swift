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
        
//        try Self.deleteStore(at: url)
        
        self.writer = try Connection(url.path)
        
        writer.busyTimeout = 2000 // 2 sec
        try writer.run("PRAGMA journal_mode = WAL")
        try writer.run("PRAGMA cache_size = 10000")
        
        self.reader = try Connection(url.path, readonly: true)
        reader.busyTimeout = 2000 // 2 Sec
        
        try createTablesIfNeeded()
    }
    
    private static func deleteStore(at url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
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
            
//            try writer.run(pointerTable.table.create(ifNotExists: true, withoutRowid: true) { t in
//                t.column(pointerTable.userID)    // FK user.serverID
//                t.column(pointerTable.messageID) // FK message.serverID
//                
//                t.primaryKey(pointerTable.userID, memberTable.roomID)
//                t.foreignKey(pointerTable.userID,    references: userTable.table, memberTable.userID,       delete: .cascade)
//                t.foreignKey(pointerTable.messageID, references: messageTable.table, messageTable.serverID, delete: .cascade)
//            })
        }
    }
}
