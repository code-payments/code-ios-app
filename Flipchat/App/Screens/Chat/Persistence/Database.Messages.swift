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

            r.content      AS rContent,
            ru.displayName AS rDisplayName,
        
            p.displayName  AS socialDisplayName,
            p.avatarURL    AS socialAvatarURL,
            p.verificationType AS socialVerificationType

        FROM
            message m

        LEFT JOIN message r ON m.referenceID = r.serverID
        LEFT JOIN user ru   ON r.senderID = ru.serverID
        LEFT JOIN user u    ON m.senderID = u.serverID
        LEFT JOIN member b  ON m.senderID = b.userID AND m.roomID = b.roomID
        LEFT JOIN profile p ON m.senderID = p.userID

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
                    content: rContent!
                )
            )
        }
        
        return messages.reversed()
    }
}

// MARK: - Types -

let defaultMemberName = "Member"

struct MessageRow: Hashable {
    
    let message: Message
    let member: Member
    let referenceID: UUID?
    let reference: Reference?
    
    struct Message: Hashable {
        let serverID: UUID
        let roomID: UUID
        let date: Date
        let state: Chat.Message.State
        let senderID: UUID?
        let contentType: ContentType
        let content: String
        let isDeleted: Bool
        let kin: Kin
        let hasTipFromSelf: Bool
        let offStage: Bool
    }
    
    struct Member: Hashable {
        let userID: UUID?
        let displayName: String?
        let isMuted: Bool?
        let isBlocked: Bool?
        let canSend: Bool?
        let profile: SocialProfile?
        
        var resolvedDisplayName: String {
            (profile?.displayName ?? displayName) ?? defaultMemberName
        }
    }
    
    struct Reference: Hashable {
        let displayName: String?
        let content: String
    }
}

struct SocialProfile: Hashable {
    let displayName: String
    let avatar: TwitterAvatar?
    let verificationType: VerificationType
    
    init(displayName: String, avatarURL: URL?, verificationType: VerificationType) {
        self.displayName = displayName
        self.verificationType = verificationType
        
        if let avatarURL {
            self.avatar = TwitterAvatar(url: avatarURL)
        } else {
            self.avatar = nil
        }
    }
}

struct SocialProfileFull: Hashable {
    let socialID: String
    let username: String
    let displayName: String
    let bio: String
    let followerCount: Int
    let avatar: TwitterAvatar?
    let verificationType: VerificationType
    
    init(socialID: String, username: String, displayName: String, bio: String, followerCount: Int, avatarURL: URL?, verificationType: VerificationType) {
        self.socialID = socialID
        self.username = username
        self.displayName = displayName
        self.bio = bio
        self.followerCount = followerCount
        self.verificationType = verificationType
        
        if let avatarURL {
            self.avatar = TwitterAvatar(url: avatarURL)
        } else {
            self.avatar = nil
        }
    }
}

struct TipUser {
    let userID: UUID
    let displayName: String?
    let tip: Kin
    let profile: SocialProfile?
    
    var resolvedDisplayName: String {
        (profile?.displayName ?? displayName) ?? defaultMemberName
    }
}

struct MessagePointer {
    let messageID: UUID
    let kind: Chat.Pointer.Kind
    let newUnreads: Int
}

// MARK: - Mapping -

extension SocialProfile {
    init?(row: RowIterator.Element) {
        let socialDisplayName = row[Expression<String?>("socialDisplayName")]
        let socialAvatarURL   = row[Expression<URL?>("socialAvatarURL")]
        let verificationType  = row[Expression<VerificationType?>("socialVerificationType")]
        
        if let socialDisplayName {
            self.init(
                displayName: socialDisplayName,
                avatarURL: socialAvatarURL,
                verificationType: verificationType ?? .none
            )
        } else {
            return nil
        }
    }
}

/// Ref: https://developer.twitter.com/en/docs/twitter-api/v1/accounts-and-users/user-profile-images-and-banners
struct TwitterAvatar: Equatable, Hashable, Codable {
    
    let mini: URL     //  24 x 24
    let normal: URL   //  48 x 48
    let bigger: URL   //  73 x 73
    let original: URL // 400 x 400?
    
    // MARK: - Init -
    
    init(normal: URL, bigger: URL, mini: URL, original: URL) {
        self.normal = normal
        self.bigger = bigger
        self.mini = mini
        self.original = original
    }
    
    init(url: URL) {
        let suffixes: Set = [
            "_normal",
            "_bigger",
            "_mini",
            "_original",
        ]
        
        var string = url.absoluteString
        
        suffixes.forEach { suffix in
            string = string.replacingOccurrences(of: suffix, with: "")
        }
        
        let baseURL = URL(string: string)!
        
        let imagePath = baseURL.lastPathComponent
        var components = imagePath.components(separatedBy: ".")
        if components.count == 2 {
            components[0] = "\(components[0])"
        }
        
        self.init(
            normal:   Self.applying(suffix: "_normal", to: baseURL),
            bigger:   Self.applying(suffix: "_bigger", to: baseURL),
            mini:     Self.applying(suffix: "_mini",   to: baseURL),
            original: baseURL
        )
    }
    
    private static func applying(suffix: String, to baseURL: URL) -> URL {
        let separator = "."
        let imagePath = baseURL.lastPathComponent
        
        var components = imagePath.components(separatedBy: separator)
        if components.count == 2 {
            components[0] = "\(components[0])\(suffix)"
        }
        let newImagePath = components.joined(separator: separator)
        
        var updatedURL = baseURL
        
        updatedURL.deleteLastPathComponent()
        updatedURL.appendPathComponent(newImagePath)
        
        return updatedURL
    }
}
