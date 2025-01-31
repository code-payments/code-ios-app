//
//  Database.Users.swift
//  Code
//
//  Created by Dima Bart on 2024-12-01.
//

import Foundation
import FlipchatServices
import SQLite

extension Database {
    
    func getUsers(roomID: UUID) throws -> [MemberRow] {
        let statement = try reader.prepareRowIterator("""
        SELECT 
            u.serverID,
            u.displayName,
            u.avatarURL,
            m.isMuted,
            m.canModerate,
            m.canSend
        FROM 
            member m
        LEFT JOIN
            user u
        ON
            m.userID = u.serverID
        WHERE 
            m.roomID = "\(roomID.uuidString)";
        """)
        
        let mTable = MemberTable()
        let uTable = UserTable()
        
        let members = try statement.map { row in
            MemberRow(
                serverID:    row[uTable.serverID],
                displayName: row[uTable.displayName],
                avatarURL:   row[uTable.avatarURL],
                isMuted:     row[mTable.isMuted],
                canModerate: row[mTable.canModerate],
                canSend:     row[mTable.canSend]
            )
        }
        
        return members
    }
    
    func getUser(userID: UUID, roomID: UUID) throws -> MemberRow? {
        let statement = try reader.prepareRowIterator("""
        SELECT 
            u.serverID,
            u.displayName,
            u.avatarURL,
            m.isMuted,
            m.canModerate,
            m.canSend
        FROM 
            member m
        LEFT JOIN
            user u
        ON
            m.userID = u.serverID
        WHERE 
            serverID = "\(userID.uuidString)" AND
            m.roomID = "\(roomID.uuidString)"
        LIMIT 1;
        """)
        
        let mTable = MemberTable()
        let uTable = UserTable()
        
        let members = try statement.map { row in
            MemberRow(
                serverID:    row[uTable.serverID],
                displayName: row[uTable.displayName],
                avatarURL:   row[uTable.avatarURL],
                isMuted:     row[mTable.isMuted],
                canModerate: row[mTable.canModerate],
                canSend:     row[mTable.canSend]
            )
        }
        
        return members.first
    }
}

// MARK: - Types -

struct MemberRow {
    let serverID: UUID
    let displayName: String?
    let avatarURL: URL?
    let isMuted: Bool
    let canModerate: Bool
    let canSend: Bool
}
