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
            m.canSend,
                    
            p.displayName  AS socialDisplayName,
            p.avatarURL    AS socialAvatarURL,
            p.verificationType AS socialVerificationType
        
        FROM 
            member m
        
        LEFT JOIN user u    ON m.userID = u.serverID
        LEFT JOIN profile p ON m.userID = p.userID
        
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
                canSend:     row[mTable.canSend],
                profile:     .init(row: row)
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
            m.canSend,
                    
            p.displayName  AS socialDisplayName,
            p.avatarURL    AS socialAvatarURL,
            p.verificationType AS socialVerificationType

        FROM 
            member m

        LEFT JOIN user u    ON m.userID = u.serverID
        LEFT JOIN profile p ON m.userID = p.userID

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
                canSend:     row[mTable.canSend],
                profile:     .init(row: row)
            )
        }
        
        return members.first
    }
    
    func getUserProfile(userID: UUID) throws -> UserProfileRow? {
        let statement = try reader.prepareRowIterator("""
        SELECT
            u.serverID,
            u.displayName,
            u.avatarURL,
                    
            p.socialID         AS socialID,
            p.username         AS socialUsername,
            p.displayName      AS socialDisplayName,
            p.bio              AS socialBio,
            p.followerCount    AS socialFollowerCount,
            p.avatarURL        AS socialAvatarURL,
            p.verificationType AS socialVerificationType

        FROM
            user u

        LEFT JOIN profile p ON u.serverID = p.userID

        WHERE
            serverID = "\(userID.uuidString)"
        LIMIT 1;
        """)
        
        let uTable = UserTable()
        
        let profiles = try statement.map { row in
            UserProfileRow(
                serverID:    row[uTable.serverID],
                displayName: row[uTable.displayName],
                avatarURL:   row[uTable.avatarURL],
                profile:     .init(row: row)
            )
        }
        
        return profiles.first
    }
    
    func getTypingProfiles(userIDs: [UUID]) throws -> [TypingProfile] {
        let usersQuery = userIDs.map { "\"\($0.uuidString)\"" }.joined(separator: ", ")
        let statement = try reader.prepareRowIterator("""
        SELECT
            u.serverID,
            u.avatarURL,
        
            p.displayName      AS socialDisplayName,
            p.avatarURL        AS socialAvatarURL,
            p.verificationType AS socialVerificationType
            
        FROM
            user u

        LEFT JOIN profile p ON u.serverID = p.userID

        WHERE
            serverID IN(\(usersQuery))
        ORDER BY
            socialVerificationType DESC, serverID DESC;
        """)
        
        let uTable = UserTable()
        
        let typingUsers = try statement.compactMap { row in
            TypingProfile(
                serverID:      row[uTable.serverID],
                avatarURL:     row[uTable.avatarURL],
                socialProfile: .init(row: row)
            )
        }
        
        return typingUsers
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
    let profile: SocialProfile?
    
    var resolvedDisplayName: String {
        (profile?.displayName ?? displayName) ?? defaultMemberName
    }
}

struct UserProfileRow {
    let serverID: UUID
    let displayName: String?
    let avatarURL: URL?
    let profile: SocialProfileFull?
    
    var resolvedDisplayName: String {
        (profile?.displayName ?? displayName) ?? defaultMemberName
    }
}

struct TypingProfile {
    let serverID: UUID
    let avatarURL: URL?
    let socialProfile: SocialProfile?
    
    init(serverID: UUID, avatarURL: URL?, socialProfile: SocialProfile?) {
        self.serverID = serverID
        self.avatarURL = avatarURL
        self.socialProfile = socialProfile
    }
}
