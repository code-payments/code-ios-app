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

            m.serverID AS mServerID,
            m.roomID   AS mRoomID,
            m.date     AS mDate,
            m.state    AS mState,
            m.senderID AS mSenderID,
            m.contents AS mContents,

            memberCount.count AS memberCount,
            u.displayName AS hostDisplayName
        FROM
            room r
        LEFT JOIN (
            SELECT
                roomID,
                MAX(date) AS maxDate
            FROM
                message
            GROUP BY
                roomID
        ) AS latestMessage
        ON
            r.serverID = latestMessage.roomID
        LEFT JOIN message m
        ON
            latestMessage.roomID = m.roomID
            AND latestMessage.maxDate = m.date
        LEFT JOIN (
            SELECT
                roomID,
                COUNT(*) AS count
            FROM
                member
            GROUP BY
                roomID
        ) AS memberCount
        ON
            r.serverID = memberCount.roomID
        LEFT JOIN user u
        ON
            r.ownerUserID = u.serverID
        WHERE r.serverID = "\(roomID.uuidString)"
        LIMIT 1;
        """)
        
        let rTable = RoomTable()
        let mTable = MessageTable()
        
        let rooms = try statement.map { row in
            RoomDescription(
                room: .init(
                    serverID:    row[rTable.serverID],
                    kind:        row[rTable.kind],
                    title:       row[rTable.title],
                    roomNumber:  row[rTable.roomNumber],
                    ownerUserID: row[rTable.ownerUserID],
                    cover:       Kin(quarks: row[rTable.coverQuarks])!,
                    unreadCount: row[rTable.unreadCount],
                    isDeleted:   row[rTable.isDeleted]
                ),
                lastMessage: .init(
                    serverID:    row[mTable.serverID.alias("mServerID")],
                    roomID:      row[mTable.roomID.alias("mRoomID")],
                    date:        row[mTable.date.alias("mDate")],
                    state:       row[mTable.state.alias("mState")],
                    senderID:    row[mTable.senderID.alias("mSenderID")],
                    contents:    row[mTable.contents.alias("mContents")]
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

            m.serverID AS mServerID,
            m.roomID   AS mRoomID,
            m.date     AS mDate,
            m.state    AS mState,
            m.senderID AS mSenderID,
            m.contents AS mContents
        FROM
            room r
        INNER JOIN (
            SELECT
                roomID,
                MAX(date) AS maxDate
            FROM
                message
            GROUP BY
                roomID
        ) AS latestMessage
        ON
            r.serverID = latestMessage.roomID
        INNER JOIN message m
        ON
            latestMessage.roomID = m.roomID
            AND latestMessage.maxDate = m.date
        ORDER BY m.date DESC;
        """)
        
        let rTable = RoomTable()
        let mTable = MessageTable()
        
        let rooms = try statement.map { row in
            RoomRow(
                room: .init(
                    serverID:    row[rTable.serverID],
                    kind:        row[rTable.kind],
                    title:       row[rTable.title],
                    roomNumber:  row[rTable.roomNumber],
                    ownerUserID: row[rTable.ownerUserID],
                    cover:       Kin(quarks: row[rTable.coverQuarks])!,
                    unreadCount: row[rTable.unreadCount],
                    isDeleted:   row[rTable.isDeleted]
                ),
                lastMessage: .init(
                    serverID:    row[mTable.serverID.alias("mServerID")],
                    roomID:      row[mTable.roomID.alias("mRoomID")],
                    date:        row[mTable.date.alias("mDate")],
                    state:       row[mTable.state.alias("mState")],
                    senderID:    row[mTable.senderID.alias("mSenderID")],
                    contents:    row[mTable.contents.alias("mContents")]
                )
            )
        }
        
        return rooms
    }
}

// MARK: - Types -

struct RoomDescription {
    
    let room: Room
    let lastMessage: Message
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
    }
    
    struct Message {
        let serverID: UUID
        let roomID: UUID
        let date: Date
        let state: Int
        let senderID: UUID?
        let contents: ContentContainer
    }
}

struct RoomRow: Identifiable {
    
    var id: UUID {
        room.serverID
    }
    
    let room: Room
    let lastMessage: Message
    
    struct Room {
        let serverID: UUID
        let kind: Int
        let title: String?
        let roomNumber: RoomNumber
        let ownerUserID: UUID
        let cover: Kin
        let unreadCount: Int
        let isDeleted: Bool
    }
    
    struct Message {
        let serverID: UUID
        let roomID: UUID
        let date: Date
        let state: Int
        let senderID: UUID?
        let contents: ContentContainer
    }
}
