//
//  Database.Rooms.swift
//  Code
//
//  Created by Dima Bart on 2024-12-01.
//

import Foundation
import FlipchatServices
import SQLite

extension Database {
    
    static let excludedContentTypesForJustMessages: String = [
        ContentType.announcement.rawValue,
        ContentType.reaction.rawValue,
        ContentType.deleteMessage.rawValue,
        ContentType.tip.rawValue,
    ].map { "\($0)" }.joined(separator: ",")
    
    static let excludedContentTypesForSorting: String = [
        ContentType.announcement.rawValue,
        ContentType.reaction.rawValue,
        ContentType.deleteMessage.rawValue,
        ContentType.tip.rawValue,
    ].map { "\($0)" }.joined(separator: ",")
    
    func getRoomID(roomNumber: RoomNumber) throws -> UUID? {
        let statement = try reader.prepareRowIterator("""
        SELECT 
            r.serverID
        FROM 
            room r
        WHERE 
            roomNumber = \(roomNumber)
        LIMIT 1;
        """)
        
        let mTable = MessageTable()
        
        let messages = try statement.map { row in
            row[mTable.serverID]
        }
        
        return messages.first
    }
    
    func getRoom(roomID: UUID) throws -> RoomDescription? {
        let statement = try reader.prepareRowIterator("""
        SELECT
            r.serverID,
            r.kind,
            r.title,
            r.roomNumber,
            r.ownerUserID,
            r.coverQuarks,
            r.unreadCount,
            r.isDeleted,
            r.isOpen,

            m.serverID    AS mServerID,
            m.roomID      AS mRoomID,
            m.date        AS mDate,
            m.state       AS mState,
            m.senderID    AS mSenderID,
            m.contentType AS mType,
            m.content     AS mContent,

            COALESCE(memberCount.count, 0) AS memberCount,
            u.displayName AS hostDisplayName
        FROM
            room r
        
        LEFT JOIN (
            SELECT
                roomID,
                MAX(date) AS maxDate
            FROM
                message
            WHERE 
                isDeleted = FALSE AND contentType NOT IN (\(Self.excludedContentTypesForJustMessages))
            GROUP BY
                roomID
        ) AS latestMessage
        ON r.serverID = latestMessage.roomID
        
        LEFT JOIN message m
        ON latestMessage.roomID = m.roomID AND latestMessage.maxDate = m.date
        
        LEFT JOIN (
            SELECT
                roomID,
                COUNT(*) AS count
            FROM
                member
            GROUP BY
                roomID
        ) AS memberCount
        ON r.serverID = memberCount.roomID
        
        LEFT JOIN user u
        ON r.ownerUserID = u.serverID
        
        WHERE r.serverID = "\(roomID.uuidString)"
        
        LIMIT 1;
        """)
        
        let rTable = RoomTable()
        let mTable = MessageTable()
        
        let rooms = try statement.map { row in
            let messageID = (try? row.get(mTable.serverID.alias("mServerID")))
            return RoomDescription(
                room: .init(
                    serverID:    row[rTable.serverID],
                    kind:        row[rTable.kind],
                    title:       row[rTable.title],
                    roomNumber:  row[rTable.roomNumber],
                    ownerUserID: row[rTable.ownerUserID],
                    cover:       Kin(quarks: row[rTable.coverQuarks])!,
                    unreadCount: row[rTable.unreadCount],
                    isDeleted:   row[rTable.isDeleted],
                    isOpen:      row[rTable.isOpen]
                ),
                lastMessage: messageID == nil ? nil : .init(
                    serverID:    row[mTable.serverID.alias("mServerID")],
                    roomID:      row[mTable.roomID.alias("mRoomID")],
                    date:        row[mTable.date.alias("mDate")],
                    state:       row[mTable.state.alias("mState")],
                    senderID:    row[mTable.senderID.alias("mSenderID")],
                    contentType: row[mTable.contentType.alias("mType")],
                    content:     row[mTable.content.alias("mContent")]
                ),
                memberCount: row[Expression<Int>("memberCount")],
                hostDisplayName: row[Expression<String?>("hostDisplayName")]
            )
        }
        
        return rooms.first
    }
    
    func getRooms() throws -> [RoomRow] {
        let statement = try reader.prepareRowIterator("""
        SELECT
            r.serverID,
            r.kind,
            r.title,
            r.roomNumber,
            r.ownerUserID,
            r.coverQuarks,
            r.unreadCount,
            r.isDeleted,
            r.isMuted,
            r.canMute,
            r.isOpen,

            m.serverID    AS mServerID,
            m.roomID      AS mRoomID,
            m.date        AS mDate,  
            m.state       AS mState,
            m.senderID    AS mSenderID,
            m.contentType AS mType,
            m.content     AS mContent
        FROM
            room r
        
        LEFT JOIN (
            SELECT
                roomID,
                MAX(date) AS maxDate
            FROM
                message
            WHERE 
                isDeleted = FALSE AND contentType NOT IN (\(Self.excludedContentTypesForJustMessages))
            GROUP BY
                roomID
        ) AS latestMessage
        ON r.serverID = latestMessage.roomID
        
        LEFT JOIN (
            SELECT
                roomID,
                serverID,
                contentType,
                MAX(date) AS maxDate
            FROM
                message
            WHERE 
                contentType NOT IN (\(Self.excludedContentTypesForSorting))
            GROUP BY
                roomID
        ) AS messageForOrder
        ON r.serverID = messageForOrder.roomID
        
        LEFT JOIN 
            message m
        ON latestMessage.roomID = m.roomID AND latestMessage.maxDate = m.date
        
        ORDER BY messageForOrder.serverID DESC;
        """)
        
        let rTable = RoomTable()
        let mTable = MessageTable()
        
        let rooms = try statement.map { row in
            let messageID = (try? row.get(mTable.serverID.alias("mServerID")))
            let unread = row[rTable.unreadCount].decodingUnreadCount()
            return RoomRow(
                room: .init(
                    serverID:      row[rTable.serverID],
                    kind:          row[rTable.kind],
                    title:         row[rTable.title],
                    roomNumber:    row[rTable.roomNumber],
                    ownerUserID:   row[rTable.ownerUserID],
                    cover:         Kin(quarks: row[rTable.coverQuarks])!,
                    unreadCount:   unread.count,
                    hasMoreUnread: unread.hasMore,
                    isOpen:        row[rTable.isOpen],
                    isDeleted:     row[rTable.isDeleted],
                    isMuted:       row[rTable.isMuted],
                    canMute:       row[rTable.canMute]
                ),
                lastMessage: messageID == nil ? nil : .init(
                    serverID:    row[mTable.serverID.alias("mServerID")],
                    roomID:      row[mTable.roomID.alias("mRoomID")],
                    date:        row[mTable.date.alias("mDate")],
                    state:       row[mTable.state.alias("mState")],
                    senderID:    row[mTable.senderID.alias("mSenderID")],
                    contentType: row[mTable.contentType.alias("mType")],
                    content:     row[mTable.content.alias("mContent")]
                )
            )
        }
        
        return rooms
    }
}

// MARK: - Types -

struct RoomDescription: Identifiable {
    
    var id: UUID {
        room.serverID
    }
    
    let room: Room
    let lastMessage: Message?
    let memberCount: Int
    let hostDisplayName: String?
    
    struct Room {
        let serverID: UUID
        let kind: Int
        let title: String?
        let roomNumber: RoomNumber
        let ownerUserID: UUID
        let cover: Kin
        let unreadCount: Int
        let isDeleted: Bool
        let isOpen: Bool
        
        var formattedTitle: String {
            if let title {
                return "\(roomNumber.formattedRoomNumberShort): \(title)"
            } else {
                return roomNumber.formattedRoomNumberShort
            }
        }
    }
    
    struct Message {
        let serverID: UUID
        let roomID: UUID
        let date: Date
        let state: Int
        let senderID: UUID?
        let contentType: ContentType
        let content: String
    }
}

struct RoomRow: Identifiable {
    
    var id: UUID {
        room.serverID
    }
    
    let room: Room
    let lastMessage: Message?
    
    struct Room {
        let serverID: UUID
        let kind: Int
        let title: String?
        let roomNumber: RoomNumber
        let ownerUserID: UUID
        let cover: Kin
        let unreadCount: Int
        let hasMoreUnread: Bool
        let isOpen: Bool
        let isDeleted: Bool
        let isMuted: Bool
        let canMute: Bool
        
        var formattedTitle: String {
            if let title {
                return "\(roomNumber.formattedRoomNumberShort): \(title)"
            } else {
                return roomNumber.formattedRoomNumberShort
            }
        }
    }
    
    struct Message {
        let serverID: UUID
        let roomID: UUID
        let date: Date
        let state: Int
        let senderID: UUID?
        let contentType: ContentType
        let content: String
    }
}
