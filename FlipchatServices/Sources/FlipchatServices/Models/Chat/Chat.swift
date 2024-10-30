//
//  ChatLegacy.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipchatAPI

@MainActor
public class Chat: ObservableObject {
    
    /// Metadata for this chat: id, kind, roomNumber, etc
    @Published public private(set) var metadata: Metadata
    
    /// The members in this chat
    ///
    /// For NOTIFICATION chats, this list has exactly 1 item
    /// For TWO_WAY chats, this list has exactly 2 items
    ///
    /// If we support group chats, then we'll likely return the first page
    /// or a prioritized list. The remaining members would be fetched via
    /// a new RPC.
//    @Published public private(set) var members: [Member]
    
    /// The messages in this chat
    @Published public private(set) var messages: [Message]
        
    public let selfUserID: UserID
    
    public var id: ChatID {
        metadata.id
    }
    
    public var kind: Chat.Kind {
        metadata.kind
    }
    
    public var roomNumber: RoomNumber {
        metadata.roomNumber
    }
    
    public var isMuted: Bool {
        metadata.isMuted
    }
    
    public var isMutable: Bool {
        metadata.isMutable
    }
    
    public var unreadCount: Int {
        metadata.unreadCount
    }
    
    /// A member of the `members` array that is `self`
//    public var selfMember: Member? {
//        members.first { $0.isSelf }
//    }
//    
//    /// In a two-way chat, the member that isn't `self`
//    public var otherMember: Member? {
//        guard members.count == 2 else {
//            return nil
//        }
//        
//        return members.first { !$0.isSelf }
//    }
    
    /// In a two-way chat, the other member's avatar URL
//    public var otherMemberAvatarURL: URL? {
//        otherMember?.identity.avatarURL
//    }
    
    /// The title for the chat that defaults to identifying the 'other'
    /// member if their identity is available, otherwise `title`
    public var displayName: String {
        "Room #\(roomNumber)"
    }
    
//    public var recipientPointers: [Pointer] {
//        guard members.count == 2 else {
//            return []
//        }
//        
//        let recipient = members.first { !$0.isSelf }
//        return recipient?.pointers ?? []
//    }
    
    public var oldestMessage: Message? {
        messages.first
    }
    
    public var newestMessage: Message? {
        messages.last
    }
    
    // MARK: - Init -
    
    public init(selfUserID: UserID, metadata: Metadata, messages: [Message] = []) {
        self.selfUserID = selfUserID
        self.metadata = metadata
        self.messages = messages
    }
    
    // MARK: - State -
    
    public func resetUnreadCount() {
        metadata.unreadCount = 0
    }
    
    public func setMuted(_ muted: Bool) {
        metadata.isMuted = muted
    }
    
//    private func updatingSelf(block: (inout Member) -> Void) {
//        if let index = members.firstIndex(where: { $0.isSelf }) {
//            block(&members[index])
//        }
//    }
    
    // MARK: - Pointers -
    
//    public func setPointer(_ pointer: Pointer) {
//        guard let memberIndex = members.firstIndex(where: { $0.id == pointer.memberID }) else {
//            return
//        }
//        
//        var memberToUpdate = members[memberIndex]
//        
//        guard let index = memberToUpdate.pointers.firstIndex(where: { $0.kind == pointer.kind }) else {
//            return
//        }
//        
//        memberToUpdate.pointers[index] = pointer
//        members[memberIndex] = memberToUpdate
//        
//        objectWillChange.send()
//    }
    
    // MARK: - Messages -
    
    public func isMessageReceived(_ userID: UserID?) -> Bool {
        userID != selfUserID
    }
    
    @discardableResult
    public func insertMessages(_ messages: [Message]) -> Int {
        var newMessages = messages.elementsKeyed(by: \.id)
        
        // Iterate over existing messages and replace with
        // any new messages and then removing them from 'new'.
        // We'll append the rest of the 'new' messages and
        // sort the whole array.
        
        var updatedMessages: [Message] = []
        updatedMessages.reserveCapacity(messages.count)
        
        for existingMessage in self.messages {
            let id = existingMessage.id
            if let newMessage = newMessages[id] {
                newMessages.removeValue(forKey: id)
                updatedMessages.append(newMessage)
            } else {
                updatedMessages.append(existingMessage)
            }
        }
        
        setSortedMessages((self.messages + newMessages.values).sortedByDateDesc())
        
        return newMessages.count
    }
    
    public func setMessages(_ messages: [Message]) {
        setSortedMessages(messages.sortedByDateDesc())
    }
    
    private func setSortedMessages(_ messages: [Message]) {
        self.messages = messages
    }
    
    public func latestMessage() -> Message? {
        messages.last // Order is ascending
    }
    
    public func popLast() -> Message? {
        messages.popLast()
    }
    
    @discardableResult
    public func update(from metadata: Metadata) -> Bool {
        guard metadata.id == id else {
            return false
        }
        
        self.metadata = metadata
        
        return true
    }
    
//    @discardableResult
//    public func update(from chat: Chat) -> Bool {
//        guard chat.id == id else {
//            return false
//        }
//        
//        kind = chat.kind
//        members = chat.members
//        messages = chat.messages
//        
//        return true
//    }
}

//extension Chat: Hashable, Equatable {
//    nonisolated
//    public static func == (lhs: Chat, rhs: Chat) -> Bool {
//        lhs.metadata.id == rhs.metadata.id
//    }
//    
//    nonisolated
//    public func hash(into hasher: inout Hasher) {
//        hasher.combine(id)
//    }
//}

//extension Chat {
//    public enum Kind: Int {
//        case unknown
//        case twoWay
//        case group
//    }
//}

extension Chat {
    public enum Verb: Equatable, Hashable, Sendable {
        case unknown     // = 0
        case gave        // = 1
        case received    // = 2
        case withdrew    // = 3
        case deposited   // = 4
        case sent        // = 5
        case returned    // = 6
        case spent       // = 7
        case paid        // = 8
        case purchased   // = 9
        case tipReceived // = 10
        case tipSent     // = 11
    }
}

// MARK: - Proto -

//extension Chat {
//    public convenience init(_ proto: Flipchat_Chat_V1_Metadata) {
//        self.init(
//            id: .init(data: proto.chatID.value),
//            roomNumber: proto.roomNumber,
//            kind: Kind(rawValue: proto.type.rawValue) ?? .unknown,
//            isMuted: proto.isMuted,
//            muteable: proto.muteable,
//            unreadCount: Int(proto.numUnread),
//            members: proto.members.map { .init($0) },
//            messages: []
//        )
//    }
//}

// MARK: - Description -

//extension Chat: CustomDebugStringConvertible, CustomStringConvertible {
//    
//    nonisolated
//    public var description: String {
////        let messages = messages.map { message in
////            "\(message.date) \(message.id.data.hexEncodedString())"
////        }.joined(separator: "\n")
//        
//        return "\(id.data.hexEncodedString())"// (\(String(describing: title))\n\(messages)"
//    }
//    
//    nonisolated
//    public var debugDescription: String {
//        description
//    }
//}
