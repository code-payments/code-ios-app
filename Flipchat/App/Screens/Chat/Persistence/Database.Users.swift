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
}

struct UserProfileRow {
    let serverID: UUID
    let displayName: String?
    let avatarURL: URL?
    let profile: SocialProfileFull?
}

struct SocialProfileFull: Hashable {
    let socialID: String
    let username: String
    let displayName: String
    let bio: String
    let followerCount: Int
    let avatarURL: URL?
    let verificationType: VerificationType
}

// MARK: - Mapping -

extension SocialProfileFull {
    init?(row: RowIterator.Element) {
        let socialID            = row[Expression<String?>("socialID")]
        let socialUsername      = row[Expression<String?>("socialUsername")]
        let socialDisplayName   = row[Expression<String?>("socialDisplayName")]
        let socialBio           = row[Expression<String?>("socialBio")]
        let socialFollowerCount = row[Expression<Int?>("socialFollowerCount")]
        let socialAvatarURL     = row[Expression<URL?>("socialAvatarURL")]
        let verificationType    = row[Expression<VerificationType?>("socialVerificationType")]
        
        if
            let socialID,
            let socialDisplayName,
            let socialUsername,
            let socialBio,
            let socialFollowerCount
        {
            self.init(
                socialID: socialID,
                username: socialUsername,
                displayName: socialDisplayName,
                bio: socialBio,
                followerCount: socialFollowerCount,
                avatarURL: socialAvatarURL,
                verificationType: verificationType ?? .none
            )
        } else {
            return nil
        }
    }
}

