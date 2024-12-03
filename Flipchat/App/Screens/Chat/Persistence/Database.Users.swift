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
    
    /// Incomplete Chat.Member
    func getUser(userID: UUID) throws -> Chat.Member {
        let statement = try reader.prepareRowIterator("""
        SELECT 
            u.serverID,
            u.displayName,
            u.avatarURL,
            m.isMuted
        FROM 
            member m
        LEFT JOIN
            user u
        ON
            m.userID = u.serverID
        WHERE 
            serverID = "\(userID.uuidString)"
        LIMIT 1;
        """)
        
        let mTable = MemberTable()
        let uTable = UserTable()
        
        let members = try statement.map { row in
            Chat.Member(
                id: UserID(data: row[uTable.serverID].data),
                isSelf: false, // Not stored locally
                isHost: false, // Not stored locally
                isMuted: row[mTable.isMuted],
                identity: .init(
                    displayName: row[uTable.displayName],
                    avatarURL: row[uTable.avatarURL]
                ),
                pointers: [] // Not stored locally (yet)
            )
        }
        
        guard let user = members.first else {
            throw GenericError(code: 1)
        }
        
        return user
    }
}

// MARK: - Types -

