//
//  Database.Writer.swift
//  Code
//
//  Created by Dima Bart on 2024-11-30.
//

import Foundation
import FlipchatServices
@preconcurrency import SQLite

extension Database {
        
    func transaction(_ block: (Database) throws -> Void) throws {
//        let start = Date.now
        try writer.transaction { [unowned self] in
            try block(self)
        }
//        print("[DB TX]: \(Date.now.timeIntervalSince1970 - start.timeIntervalSince1970) seconds")
        
        commit?()
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
                table.title       <- room.title.isEmpty ? nil : room.title,
                table.roomNumber  <- room.roomNumber,
                table.ownerUserID <- room.ownerUser.uuid,
                table.coverQuarks <- Int64(room.coverAmount.quarks),
                table.unreadCount <- room.unreadCount,
                table.isMuted     <- room.isMuted,
                table.canMute     <- room.canMute,
                
                onConflictOf: table.serverID
            )
        )
    }

    func clearUnread(chatID: ChatID) throws {
        let room = RoomTable()
        try writer.run(
            room.table
                .filter(room.serverID == chatID.uuid)
                .update(room.unreadCount <- 0)
        )
    }

    func deleteRoom(chatID: ChatID) throws {
        let room = RoomTable()
        try writer.run(
            room.table
                .filter(room.serverID == chatID.uuid)
                .delete()
        )
    }
    
    func muteMember(userID: UUID, muted: Bool) throws {
        let member = MemberTable()
        try writer.run(
            member.table
                .filter(member.userID == userID)
                .update(member.isMuted <- muted)
        )
    }
    
    func muteChat(roomID: UUID, muted: Bool) throws {
        let room = RoomTable()
        try writer.run(
            room.table
                .filter(room.serverID == roomID)
                .update(room.isMuted <- muted)
        )
    }

    func insertMessages(messages: [Chat.Message], chatID: ChatID, isBatch: Bool) throws {
        let message = MessageTable()
        try messages.forEach {
            try insertMessage(message: $0, roomID: chatID.uuid, isBatch: isBatch, into: message)
        }
    }
    
    func insertMembers(members: [Chat.Member], chatID: ChatID) throws {
        let member = MemberTable()
        let user = UserTable()
        try members.forEach {
            try insertMember(member: $0, roomID: chatID.uuid, into: member)
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
    
    // MARK: - Private -

    private func insertMessage(message: Chat.Message, roomID: UUID, isBatch: Bool, into table: MessageTable) throws {
        try writer.run(
            table.table.upsert(
                table.serverID    <- message.id.uuid,
                table.roomID      <- roomID,
                table.date        <- message.date,
                table.state       <- Chat.Message.State.delivered.rawValue,
                table.senderID    <- message.senderID?.uuid,
                table.contents    <- ContentContainer(contents: message.contents.compactMap { .init(content: $0) }),
                table.isBatch     <- isBatch,
                
                onConflictOf: table.serverID
            )
        )
    }

    private func insertMember(member: Chat.Member, roomID: UUID, into table: MemberTable) throws {
        try writer.run(
            table.table.upsert(
                table.userID      <- member.id.uuid,
                table.roomID      <- roomID,
                table.isMuted     <- member.isMuted,
                
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
