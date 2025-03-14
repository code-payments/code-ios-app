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
    
    func getPointer(userID: UUID, roomID: UUID) throws -> MessagePointer? {
        let statement = try reader.prepareRowIterator("""
        SELECT
            p.kind,
            p.messageID,
            (
                SELECT 
                    COUNT(*)
                FROM 
                    message m
                WHERE 
                    m.roomID = "\(roomID.uuidString)" AND 
                    m.serverID > p.messageID AND
                    contentType NOT IN (\(Self.excludedContentTypesForJustMessages))
            ) AS newUnreads
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
                kind: Chat.Pointer.Kind(rawValue: row[pTable.kind])!,
                newUnreads: row[Expression<Int>("newUnreads")]
            )
        }
        
        return pointers.first
    }
    
    func getTipUsers(messageID: UUID) throws -> [TipUser] {
        let statement = try reader.prepareRowIterator("""
        SELECT
            u.serverID    AS userID,
            u.displayName AS displayName,
            SUM(t.kin)    AS tip,
        
            p.displayName  AS socialDisplayName,
            p.avatarURL    AS socialAvatarURL,
            p.verificationType AS socialVerificationType
        
        FROM 
            message m
        
        LEFT JOIN message t ON t.referenceID = m.serverID AND t.contentType = 4
        LEFT JOIN user u    ON t.senderID = u.serverID
        LEFT JOIN profile p ON u.serverID = p.userID
        
        WHERE m.serverID = "\(messageID)"
        GROUP BY u.serverID, u.displayName
        
        ORDER BY tip DESC;
        """)
        
        return try statement.map { row in
            TipUser(
                userID:      row[Expression<UUID>("userID")],
                displayName: row[Expression<String?>("displayName")],
                tip:         Kin(quarks: row[Expression<UInt64>("tip")]),
                profile:     .init(row: row)
            )
        }
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
            m.referenceID,
            m.isDeleted,
            m.kin,
            m.hasTipFromSelf,
            m.offStage,

            u.serverID     AS uServerID,
            u.displayName  AS uDisplayName,
            u.isBlocked    AS uIsBlocked,
            b.isMuted      AS uIsMuted,
            b.canSend      AS uCanSend,

            r.content           AS rContent,
            ru.displayName      AS rDisplayName,
            rp.displayName      AS rSocialDisplayName,
            rp.avatarURL        AS rSocialAvatarURL,
            rp.verificationType AS rSocialVerificationType,

            p.displayName      AS socialDisplayName,
            p.avatarURL        AS socialAvatarURL,
            p.verificationType AS socialVerificationType

        FROM
            message m

        LEFT JOIN message r  ON m.referenceID = r.serverID
        LEFT JOIN user ru    ON r.senderID    = ru.serverID
        LEFT JOIN user u     ON m.senderID    = u.serverID
        LEFT JOIN member b   ON m.senderID    = b.userID AND m.roomID = b.roomID
        LEFT JOIN profile p  ON m.senderID    = p.userID
        LEFT JOIN profile rp ON r.senderID    = rp.userID

        WHERE 
            m.roomID = "\(roomID.uuidString)"
        ORDER BY m.serverID DESC
        LIMIT \(pageSize) OFFSET \(offset);
        """)
        
        let mTable = MessageTable()
        
        let messages = try statement.map { row in
            let referenceID = row[Expression<UUID?>("referenceID")]
            let rDisplayName = row[Expression<String?>("rDisplayName")]
            let rContent = row[Expression<String?>("rContent")]
            
            return MessageRow(
                message: .init(
                    serverID:       row[mTable.serverID],
                    roomID:         row[mTable.roomID],
                    date:           row[mTable.date],
                    state:          .init(rawValue: row[mTable.state]) ?? .sent,
                    senderID:       row[mTable.senderID],
                    contentType:    row[mTable.contentType],
                    content:        row[mTable.content],
                    isDeleted:      row[mTable.isDeleted],
                    kin:            Kin(quarks: row[mTable.kin]),
                    hasTipFromSelf: row[mTable.hasTipFromSelf],
                    offStage:       row[mTable.offStage]
                ),
                member: .init(
                    userID:      row[Expression<UUID?>("uServerID")],
                    displayName: row[Expression<String?>("uDisplayName")],
                    isMuted:     row[Expression<Bool?>("uIsMuted")],
                    isBlocked:   row[Expression<Bool?>("uIsBlocked")],
                    canSend:     row[Expression<Bool?>("uCanSend")],
                    profile:     .init(row: row)
                ),
                referenceID: referenceID,
                
                // Only return a reference object if a
                // local version of the reference exists
                reference: rContent == nil ? nil : .init(
                    displayName: rDisplayName,
                    content: rContent!,
                    profile: .init(rowForReference: row)
                )
            )
        }
        
        return messages.reversed()
    }
}
