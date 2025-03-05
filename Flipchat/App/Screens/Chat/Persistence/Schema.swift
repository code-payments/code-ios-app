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
    static let name = "room"
    
    let table        = Table(Self.name)
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
    let isOpen       = Expression <Bool>       ("isOpen")
}

struct MessageTable: Sendable {
    static let name = "message"
    
    let table          = Table(Self.name)
    let serverID       = Expression <UUID>        ("serverID")
    let roomID         = Expression <UUID>        ("roomID")
    let date           = Expression <Date>        ("date")
    let state          = Expression <Int>         ("state")
    let senderID       = Expression <UUID?>       ("senderID")
    let referenceID    = Expression <UUID?>       ("referenceID")
    let contentType    = Expression <ContentType> ("contentType")
    let content        = Expression <String>      ("content")
    let kin            = Expression <UInt64>      ("kin") // Quarks
    let isDeleted      = Expression <Bool>        ("isDeleted")
    let isBatch        = Expression <Bool>        ("isBatch")
    let hasTipFromSelf = Expression <Bool>        ("hasTipFromSelf")
    let offStage       = Expression <Bool>        ("offStage")
}

struct MemberTable: Sendable {
    static let name = "member"
    
    let table       = Table(Self.name)
    let userID      = Expression <UUID> ("userID")
    let roomID      = Expression <UUID> ("roomID")
    let isMuted     = Expression <Bool> ("isMuted")
    let canModerate = Expression <Bool> ("canModerate")
    let canSend     = Expression <Bool> ("canSend")
}

struct ProfileTable: Sendable {
    static let name = "profile"
    
    let table            = Table(Self.name)
    let userID           = Expression <UUID>             ("userID")
    let socialID         = Expression <String>           ("socialID")
    let username         = Expression <String>           ("username")
    let displayName      = Expression <String>           ("displayName")
    let bio              = Expression <String>           ("bio")
    let followerCount    = Expression <Int>              ("followerCount")
    let avatarURL        = Expression <URL?>             ("avatarURL")
    let verificationType = Expression <VerificationType> ("verificationType")
}

struct UserTable: Sendable {
    static let name = "user"
    
    let table       = Table(Self.name)
    let serverID    = Expression <UUID>    ("serverID")
    let displayName = Expression <String?> ("displayName")
    let avatarURL   = Expression <URL?>    ("avatarURL")
    let isBlocked   = Expression <Bool>    ("isBlocked")
}

struct PointerTable: Sendable {
    static let name = "pointer"
    
    let table     = Table(Self.name)
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
        let profileTable = ProfileTable()
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
                t.column(roomTable.isOpen,    defaultValue: true)
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
                t.column(messageTable.kin,            defaultValue: 0)
                t.column(messageTable.isDeleted,      defaultValue: false)
                t.column(messageTable.isBatch,        defaultValue: false)
                t.column(messageTable.hasTipFromSelf, defaultValue: false)
                t.column(messageTable.offStage,       defaultValue: false)
                
                t.foreignKey(messageTable.roomID, references: roomTable.table, roomTable.serverID, delete: .cascade)
            })
            
            try writer.run(memberTable.table.create(ifNotExists: true, withoutRowid: true) { t in
                t.column(memberTable.userID) // FK user.serverID
                t.column(memberTable.roomID) // FK room.serverID
                t.column(memberTable.isMuted,   defaultValue: false)
                t.column(memberTable.canModerate)
                t.column(memberTable.canSend)
                
                t.primaryKey(memberTable.userID, memberTable.roomID)
                t.foreignKey(memberTable.userID, references: userTable.table, userTable.serverID, delete: .setNull)
                t.foreignKey(memberTable.roomID, references: roomTable.table, roomTable.serverID, delete: .cascade)
            })
            
            try writer.run(profileTable.table.create(ifNotExists: true, withoutRowid: true) { t in
                t.column(profileTable.userID, primaryKey: true) // FK user.serverID
                t.column(profileTable.socialID)
                t.column(profileTable.username)
                t.column(profileTable.displayName)
                t.column(profileTable.bio)
                t.column(profileTable.followerCount, defaultValue: 0)
                t.column(profileTable.avatarURL)
                t.column(profileTable.verificationType, defaultValue: VerificationType.none)
                
                t.foreignKey(profileTable.userID, references: userTable.table, userTable.serverID, delete: .cascade)
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
                t.foreignKey(pointerTable.userID, references: userTable.table, userTable.serverID, delete: .cascade)
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
    case tip
    case deleteMessage
    case announcementActionable
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
        case .tip:
            self = .tip
        case .deleteMessage:
            self = .deleteMessage
        case .announcementActionable:
            self = .announcementActionable
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

public enum VerificationType: Int, Value {
    case none
    case blue
    case business
    case government
    
    public init(_ type: Chat.SocialProfile.VerificationType) {
        switch type {
        case .none:       self = .none
        case .blue:       self = .blue
        case .business:   self = .business
        case .government: self = .government
        }
    }
    
    public static var declaredDatatype: String {
        Int.declaredDatatype
    }

    public static func fromDatatypeValue(_ dataValue: Int64) -> VerificationType {
        VerificationType(rawValue: Int(dataValue)) ?? .none
    }

    public var datatypeValue: Int64 {
        Int64(rawValue)
    }
}

extension UInt64: @retroactive Value {
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
