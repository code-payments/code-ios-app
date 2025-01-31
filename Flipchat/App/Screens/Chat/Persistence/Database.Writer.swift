//
//  Database.Writer.swift
//  Code
//
//  Created by Dima Bart on 2024-11-30.
//

import Foundation
import FlipchatServices
@preconcurrency import SQLite

extension Notification.Name {
    static let databaseDidChange = Notification.Name("databaseDidChange")
}

extension Database {
        
    /// Always inline this function to ensure that captureError
    /// captures the function in which this was called, otherwise
    /// it will always captured in transaction {}
    @inline(__always)
    func transaction(silent: Bool = false, _ block: (Database) throws -> Void) throws {
//        let start = Date.now
        do {
            let startChangeCount = writer.totalChanges
            try writer.transaction { [unowned self] in
                try block(self)
            }
            let endChangeCount = writer.totalChanges
            
            // There are instances where we want to commit
            // the transaction but avoid notifying the UI
            // layer of the change. Also, we'll check if
            // there's been any changes in this transaction
            // to avoid reloading unnecessarily.
            if !silent {
                let changeDelta = endChangeCount - startChangeCount
                if changeDelta > 0 {
                    NotificationQueue.default.enqueue(
                        .init(
                            name: .databaseDidChange,
                            userInfo: [
                                "changeCount": changeDelta,
                            ]
                        ),
                        postingStyle: .asap,
                        coalesceMask: .onName,
                        forModes: [.common]
                    )
                    commit?()
                } else {
                    print("Transaction detected no changes. Skipping commit...")
                }
            }
            
        } catch {
            trace(.failure, components: "Transaction error: \(error)")
            ErrorReporting.captureError(error)
        }
//        print("[DB TX]: \(Date.now.timeIntervalSince1970 - start.timeIntervalSince1970) seconds")
    }

    func insertRooms(rooms: [Chat.Metadata]) throws {
        let room = RoomTable()
        try rooms.forEach {
            try insertRoom(room: $0, into: room)
        }
    }

    private func insertRoom(room: Chat.Metadata, into table: RoomTable) throws {
        try writer.run(
            table.table.upsert(
                table.serverID    <- room.id.uuid,
                table.kind        <- room.kind.rawValue,
                table.title       <- room.title,
                table.roomNumber  <- room.roomNumber,
                table.ownerUserID <- room.ownerUser.uuid,
                table.coverQuarks <- Int64(room.coverAmount.quarks),
                table.unreadCount <- room.unreadCount.encodingUnreadCount(hasMore: room.hasMoreUnread),
                table.isMuted     <- room.isMuted,
                table.canMute     <- room.canMute,
                table.isOpen      <- room.isOpen,
                
                onConflictOf: table.serverID
            )
        )
    }

    func clearUnread(roomID: UUID) throws {
        let room = RoomTable()
        try writer.run(
            room.table
                .filter(room.serverID == roomID)
                .update(room.unreadCount <- 0)
        )
    }

    func deleteRoom(roomID: UUID) throws {
        let room = RoomTable()
        try writer.run(
            room.table
                .filter(room.serverID == roomID)
                .delete()
        )
    }
    
    func setMemberMuted(userID: UUID, roomID: UUID, muted: Bool) throws {
        let member = MemberTable()
        try writer.run(
            member.table
                .filter(member.userID == userID && member.roomID == roomID)
                .update(member.isMuted <- muted)
        )
    }
    
    func setUserBlocked(userID: UUID, blocked: Bool) throws {
        let user = UserTable()
        try writer.run(
            user.table
                .filter(user.serverID == userID)
                .update(user.isBlocked <- blocked)
        )
    }
    
    func muteRoom(roomID: UUID, muted: Bool) throws {
        let room = RoomTable()
        try writer.run(
            room.table
                .filter(room.serverID == roomID)
                .update(room.isMuted <- muted)
        )
    }

    func insertMessages(messages: [Chat.Message], roomID: UUID, isBatch: Bool, currentUserID: UUID) throws {
        let start = Date.now
        let message = MessageTable()
        try messages.forEach {
            try insertMessage(message: $0, roomID: roomID, isBatch: isBatch, into: message)
        }
        
        try recalculateTip(for: messages, currentUserID: currentUserID)
        print("[DATABASE] \(messages.count) Messages inserted: \(Date.now.timeIntervalSince1970 - start.timeIntervalSince1970) sec")
    }
    
    private func recalculateTip(for messages: [Chat.Message], currentUserID: UUID) throws {
        try messages.forEach { message in
            guard message.contentType == .tip else {
                return
            }
            
            guard let referenceID = message.referenceMessageID?.uuid else {
                return
            }
            
            try recalculateMessageTips(messageID: referenceID, senderID: message.senderID?.uuid, currentUserID: currentUserID)
        }
    }
    
    func insertMembers(members: [Chat.Member], roomID: UUID) throws {
        let member = MemberTable()
        let user = UserTable()
        try members.forEach {
            try insertMember(member: $0, roomID: roomID, into: member)
            try insertUser(user: $0.identity, userID: $0.id.uuid, into: user)
        }
    }
    
    private func insertUser(user: Chat.Identity, userID: UUID, into table: UserTable) throws {
        try writer.run(
            table.table.upsert(
                table.serverID    <- userID,
                table.displayName <- user.displayName,
                table.avatarURL   <- user.avatarURL,
                
                onConflictOf: table.serverID
            )
        )
    }
    
    // MARK: - Incremental Room Updates -
    
    func updateUnreadCount(roomID: UUID, unreadCount: Int, hasMore: Bool) throws {
        let room = RoomTable()
        try writer.run(
            room.table
                .filter(room.serverID == roomID)
                .update(room.unreadCount <- unreadCount.encodingUnreadCount(hasMore: hasMore))
        )
    }
    
    func updateDisplayName(roomID: UUID, displayName: String) throws {
        let room = RoomTable()
        try writer.run(
            room.table
                .filter(room.serverID == roomID)
                .update(room.title <- displayName)
        )
    }
    
    func updateCoverCharge(roomID: UUID, cover: Kin) throws {
        let room = RoomTable()
        try writer.run(
            room.table
                .filter(room.serverID == roomID)
                .update(room.coverQuarks <- Int64(cover.quarks))
        )
    }
    
    func updateOpenState(roomID: UUID, isOpen: Bool) throws {
        let room = RoomTable()
        try writer.run(
            room.table
                .filter(room.serverID == roomID)
                .update(room.isOpen <- isOpen)
        )
    }
    
    // MARK: - Incremental Member Updates -
    
    func deleteMember(userID: UUID, roomID: UUID) throws {
        let member = MemberTable()
        try writer.run(
            member.table
                .filter(member.userID == userID && member.roomID == roomID)
                .delete()
        )
    }
    
    // MARK: - Incremental Message Updates -
    
    func markMessagesDeletedIfNeeded() throws {
        try writer.run("""
        UPDATE message SET isDeleted = 1
        WHERE serverID IN (
            SELECT referenceID
            FROM message
            WHERE contentType = 5
        )
        """)
    }
    
    private func markMessageDeleted(messageID: UUID) throws {
        let message = MessageTable()
        try writer.run(
            message.table
                .filter(message.serverID == messageID)
                .update(message.isDeleted <- true)
        )
    }
    
    private func recalculateMessageTips(messageID: UUID, senderID: UUID?, currentUserID: UUID) throws {
        let hasTip = senderID == currentUserID ? "1" : "0"
        try writer.run("""
        UPDATE message SET kin = (
            SELECT
                COALESCE(SUM(kin), 0)
            FROM
                message
            WHERE
                contentType = 4 AND referenceID = "\(messageID.uuidString)"
        ), hasTipFromSelf = \(hasTip) WHERE serverID = "\(messageID.uuidString)";
        """)
    }
    
    // MARK: - Private -

    private func insertMessage(message: Chat.Message, roomID: UUID, isBatch: Bool, into table: MessageTable) throws {
        try writer.run(
            table.table.upsert(
                table.serverID    <- message.id.uuid,
                table.roomID      <- roomID,
                table.date        <- message.date,
                table.state       <- Chat.Message.State.delivered.rawValue,
                table.senderID    <- message.senderID?.uuid,
                table.referenceID <- message.referenceMessageID?.uuid,
                table.contentType <- ContentType(message.contentType),
                table.content     <- message.content,
                table.kin         <- message.kin.quarks,
                table.isBatch     <- isBatch,
                
                onConflictOf: table.serverID
            )
        )
        
        // For any messages that have side-effects, we'll
        // apply the side-effects here based on contentType
        
        switch message.contentType {
        case .deleteMessage:
            if let referenceID = message.referenceMessageID {
                try markMessageDeleted(messageID: referenceID.uuid)
            }
            
        case .tip:
            // Recalculation needs to happen after all messages have been
            // inserted, otherwise the SUM(kin) will miss any messages
            // that haven't been inserted yet
            break
//            if let referenceID = message.referenceMessageID {
//                // This might get expensive with large number of tips
//                try recalculateMessageTips(messageID: referenceID.uuid)
//            }
            
        case .text, .reply, .reaction, .announcement, .unknown:
            break
        }
    }

    private func insertMember(member: Chat.Member, roomID: UUID, into table: MemberTable) throws {
        try writer.run(
            table.table.upsert(
                table.userID      <- member.id.uuid,
                table.roomID      <- roomID,
                table.isMuted     <- member.isMuted,
                table.canModerate <- member.hasModeratorPermission,
                table.canSend     <- member.hasSendPermission,
                
                onConflictOf: Expression<Void>(literal: "\"userID\", \"roomID\"")
            )
        )
    }
    
    func insertPointer(kind: Chat.Pointer.Kind, userID: UUID, roomID: UUID, messageID: UUID) throws {
        let table = PointerTable()
        try writer.run(
            table.table.upsert(
                table.userID    <- userID,
                table.roomID    <- roomID,
                table.kind      <- kind.rawValue,
                table.messageID <- messageID,
                
                onConflictOf: Expression<Void>(literal: "\"userID\", \"roomID\"")
            )
        )
    }
}
