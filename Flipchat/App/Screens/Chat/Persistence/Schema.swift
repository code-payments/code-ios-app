//
//  Schema.swift
//  Code
//
//  Created by Dima Bart on 2024-12-01.
//

import Foundation
import FlipchatServices
@preconcurrency import SQLite

struct RoomTable: Sendable {
    let table        = Table("room")
    let serverID     = Expression <UUID>       ("serverID")
    let kind         = Expression <Int>        ("kind")
    let title        = Expression <String?>    ("title")
    let roomNumber   = Expression <RoomNumber> ("roomNumber")
    let ownerUserID  = Expression <UUID>       ("ownerUserID")
    let coverQuarks  = Expression <Int64>      ("coverQuarks")
    let unreadCount  = Expression <Int>        ("unreadCount")
    let isMuted      = Expression <Bool>       ("isMuted")
    let canMute      = Expression <Bool>       ("canMute")
    let isDeleted    = Expression <Bool>       ("isDeleted")
}

struct MessageTable: Sendable {
    let table       = Table("message")
    let serverID    = Expression <UUID>        ("serverID")
    let roomID      = Expression <UUID>        ("roomID")
    let date        = Expression <Date>        ("date")
    let state       = Expression <Int>         ("state")
    let senderID    = Expression <UUID?>       ("senderID")
    let referenceID = Expression <UUID?>       ("referenceID")
    let contentType = Expression <ContentType> ("contentType")
    let content     = Expression <String>      ("content")
    let isBatch     = Expression <Bool>        ("isBatch")
}

struct MemberTable: Sendable {
    let table       = Table("member")
    let userID      = Expression <UUID> ("userID")
    let roomID      = Expression <UUID> ("roomID")
    let isMuted     = Expression <Bool> ("isMuted")
    let canModerate = Expression <Bool> ("canModerate")
    let canSend     = Expression <Bool> ("canSend")
}

struct UserTable: Sendable {
    let table       = Table("user")
    let serverID    = Expression <UUID>    ("serverID")
    let displayName = Expression <String?> ("displayName")
    let avatarURL   = Expression <URL?>    ("avatarURL")
    let isBlocked   = Expression <Bool>    ("isBlocked")
}

struct PointerTable: Sendable {
    let table     = Table("pointer")
    let roomID    = Expression <UUID> ("roomID")
    let userID    = Expression <UUID> ("userID")
    let kind      = Expression <Int>  ("kind")
    let messageID = Expression <UUID> ("messageID")
}

extension Expression {
    func alias(_ alias: String) -> Expression<Datatype> {
        Expression(alias)
    }
    
    func casting<T>(to type: T.Type) -> Expression<T> {
        Expression<T>(template)
    }
}

// MARK: - Tables -

extension Database {
    func createTablesIfNeeded() throws {
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
                t.column(roomTable.isMuted,   defaultValue: false)
                t.column(roomTable.canMute,   defaultValue: false)
                t.column(roomTable.isDeleted, defaultValue: false)
            })
            
            try writer.run(messageTable.table.create(ifNotExists: true, withoutRowid: true) { t in
                t.column(messageTable.serverID, primaryKey: true)
                t.column(messageTable.roomID) // FK room.serverID
                t.column(messageTable.date)
                t.column(messageTable.state, defaultValue: 0) // Default: .sent
                t.column(messageTable.senderID)
                t.column(messageTable.referenceID)
                t.column(messageTable.contentType, defaultValue: .unknown)
                t.column(messageTable.content)
                t.column(messageTable.isBatch, defaultValue: false)
                
                t.foreignKey(messageTable.roomID, references: roomTable.table, roomTable.serverID, delete: .cascade)
            })
            
            try writer.run(memberTable.table.create(ifNotExists: true, withoutRowid: true) { t in
                t.column(memberTable.userID) // FK user.serverID
                t.column(memberTable.roomID) // FK room.serverID
                t.column(memberTable.isMuted,   defaultValue: false)
                t.column(memberTable.canModerate)
                t.column(memberTable.canSend)
                
                t.primaryKey(memberTable.userID, memberTable.roomID)
                t.foreignKey(memberTable.roomID, references: userTable.table, userTable.serverID, delete: .setNull)
                t.foreignKey(memberTable.roomID, references: roomTable.table, roomTable.serverID, delete: .cascade)
            })
            
            try writer.run(userTable.table.create(ifNotExists: true, withoutRowid: true) { t in
                t.column(userTable.serverID, primaryKey: true)
                t.column(userTable.displayName)
                t.column(userTable.avatarURL)
                t.column(userTable.isBlocked, defaultValue: false)
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

// MARK: - Types -

enum ContentType: Int, Value {
    
    case text
    case announcement
    case reaction
    case reply
    case unknown = -1
    
    init(_ content: Chat.Message.ContentType) {
        switch content {
        case .text:
            self = .text
        case .announcement:
            self = .announcement
        case .reaction:
            self = .reaction
        case .reply:
            self = .reply
        case .unknown:
            self = .unknown
        }
    }
    
    public static var declaredDatatype: String {
        Int.declaredDatatype
    }

    public static func fromDatatypeValue(_ dataValue: Int64) -> ContentType {
        ContentType(rawValue: Int(dataValue)) ?? .unknown
    }

    public var datatypeValue: Int64 {
        Int64(rawValue)
    }
}

extension UInt64: Value {
    public static var declaredDatatype: String {
        Int64.declaredDatatype
    }

    public static func fromDatatypeValue(_ dataValue: Int64) -> UInt64 {
        RoomNumber(dataValue)
    }

    public var datatypeValue: Int64 {
        Int64(self)
    }
}
