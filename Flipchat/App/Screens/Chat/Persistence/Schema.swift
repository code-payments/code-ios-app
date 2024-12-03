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
    let isDeleted    = Expression <Bool>       ("isDeleted")
}

struct MessageTable: Sendable {
    let table    = Table("message")
    let serverID = Expression <UUID>             ("serverID")
    let roomID   = Expression <UUID>             ("roomID")
    let date     = Expression <Date>             ("date")
    let state    = Expression <Int>              ("state")
    let senderID = Expression <UUID?>            ("senderID")
    let contents = Expression <ContentContainer> ("contents")
}

struct MemberTable: Sendable {
    let table   = Table("member")
    let userID  = Expression <UUID> ("userID")
    let roomID  = Expression <UUID> ("roomID")
    let isMuted = Expression <Bool> ("isMuted")
}

struct UserTable: Sendable {
    let table       = Table("user")
    let serverID    = Expression <UUID>    ("serverID")
    let displayName = Expression <String?> ("displayName")
    let avatarURL   = Expression <URL?>    ("avatarURL")
}

struct PointerTable: Sendable {
    let table     = Table("pointer")
    let userID    = Expression <UUID> ("userID")
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

// MARK: - Types -

struct ContentContainer: Value, Codable, Hashable, Equatable {
    
    enum Content: Equatable, Hashable, Sendable, Codable {
        case text(String)
        case announcement(String)
        
        var text: String {
            switch self {
            case .text(let text):
                return text
            case .announcement(let text):
                return text
            }
        }
        
        init?(content: Chat.Content) {
            switch content {
            case .text(let text):
                self = .text(text)
            case .announcement(let text):
                self = .announcement(text)
            case .sodiumBox:
                return nil
            }
        }
    }
    
    var contents: [Content]
    
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()
    
    public static var declaredDatatype: String {
        String.declaredDatatype
    }

    public static func fromDatatypeValue(_ dataValue: String) -> ContentContainer {
        try! Self.decoder.decode(ContentContainer.self, from: Data(dataValue.utf8))// ?? ContentContainer(contents: [])
    }

    public var datatypeValue: String {
        String(data: try! Self.encoder.encode(self), encoding: .utf8)!
    }
    
    // MARK: - Preview -
    
    public var contentPreview: String {
        guard !contents.isEmpty else {
            return "No content"
        }
        
        return contents.map { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
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

extension BinaryInteger {
    public var formattedRoomNumber: String {
        "Room #\(self)"
    }
}
