//
//  Database.Messages.swift
//  Code
//
//  Created by Dima Bart on 2024-12-01.
//

import Foundation
import FlipchatServices
import SQLite

extension Database {
    
    func getLatestMessageID(roomID: UUID, batchOnly: Bool) throws -> UUID? {
        let batchClause = "AND isBatch = true"
        let statement = try reader.prepareRowIterator("""
        SELECT 
            m.serverID
        FROM 
            message m
        WHERE 
            roomID = "\(roomID.uuidString)" \(batchOnly ? batchClause : "")
        ORDER BY m.serverID DESC 
        LIMIT 1;
        """)
        
        let mTable = MessageTable()
        
        let messages = try statement.map { row in
            row[mTable.serverID]
        }
        
        return messages.first
    }
    
    func getPointerMessageID(roomID: UUID, userID: UUID) throws -> MessagePointer? {
        let statement = try reader.prepareRowIterator("""
        SELECT
            p.kind,
            p.messageID
        FROM
            pointer p
        WHERE
            p.userID = "\(userID.uuidString)" AND
            p.roomID = "\(roomID.uuidString)"
        LIMIT 1;
        """)
        
        let pTable = PointerTable()
        
        let pointers = try statement.map { row in
            MessagePointer(
                messageID: row[pTable.messageID],
                kind: Chat.Pointer.Kind(rawValue: row[pTable.kind])!
            )
        }
        
        return pointers.first
    }
    
    func getMessages(roomID: UUID, pageSize: Int, offset: Int) throws -> [MessageRow] {
        let statement = try reader.prepareRowIterator("""
        SELECT
            m.serverID,
            m.roomID,
            m.date,
            m.state,
            m.senderID,
            m.contentType,
            m.content,

            u.serverID AS uServerID,
            u.displayName AS uDisplayName,
            b.isMuted AS uIsMuted
        FROM
            message m
        LEFT JOIN
            user u
        ON m.senderID = u.serverID
        LEFT JOIN
            member b
        ON m.senderID = b.userID AND m.roomID = b.roomID
        WHERE 
            m.roomID = "\(roomID.uuidString)"
        ORDER BY m.serverID ASC
        LIMIT \(pageSize) OFFSET \(offset);
        """)
        
        let mTable = MessageTable()
        
        let messages = try statement.map { row in
            MessageRow(
                message: .init(
                    serverID:    row[mTable.serverID],
                    roomID:      row[mTable.roomID],
                    date:        row[mTable.date],
                    state:       .init(rawValue: row[mTable.state]) ?? .sent,
                    senderID:    row[mTable.senderID],
                    contentType: row[mTable.contentType],
                    content:     row[mTable.content]
                ),
                member: .init(
                    userID:      row[Expression<UUID?>("uServerID")],
                    displayName: row[Expression<String?>("uDisplayName")],
                    isMuted:     row[Expression<Bool?>("uIsMuted")]
                )
            )
        }
        
        return messages
    }
}

// MARK: - Types -

struct MessageRow: Hashable {
    
    let message: Message
    let member: Member
    
    struct Message: Hashable {
        let serverID: UUID
        let roomID: UUID
        let date: Date
        let state: Chat.Message.State
        let senderID: UUID?
        let contentType: ContentType
        let content: String
    }
    
    struct Member: Hashable {
        let userID: UUID?
        let displayName: String?
        let isMuted: Bool?
    }
}

struct MessagePointer {
    let messageID: UUID
    let kind: Chat.Pointer.Kind
}
