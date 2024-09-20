//
//  Chat.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

public typealias Cursor = ID
public typealias ChatID = ID
public typealias MemberID = ID
public typealias MessageID = ID

@MainActor
public class Chat: ObservableObject {
    
    /// The members in this chat
    ///
    /// For NOTIFICATION chats, this list has exactly 1 item
    /// For TWO_WAY chats, this list has exactly 2 items
    ///
    /// If we support group chats, then we'll likely return the first page
    /// or a prioritized list. The remaining members would be fetched via
    /// a new RPC.
    @Published public private(set) var members: [Member]
    
    /// The messages in this chat
    @Published public private(set) var messages: [Message]
    
    /// Unique chat identifier
    public let id: ChatID
    
    /// Cursor value for this chat for reference in subsequent GetChatsRequest
    public private(set) var cursor: Cursor
    
    /// The type of chat
    public private(set) var kind: Kind
    
    /// The chat title, which will be localized by server when applicable
    public private(set) var title: String
    
    /// Can the user mute this chat?
    public private(set) var canMute: Bool
    
    /// Can the user unsubscribe from this chat?
    public private(set) var canUnsubscribe: Bool
    
    /// A member of the `members` array that is `self`
    public var selfMember: Member? {
        members.first { $0.isSelf }
    }
    
    /// In a two-way chat, the member that isn't `self`
    public var otherMember: Member? {
        guard members.count == 2 else {
            return nil
        }
        
        return members.first { !$0.isSelf }
    }
    
    /// In a two-way chat, the other member's avatar URL
    public var otherMemberAvatarURL: URL? {
        otherMember?.identity.avatarURL
    }
    
    /// The title for the chat that defaults to identifying the 'other'
    /// member if their identity is available, otherwise `title`
    public var displayName: String {
        otherMember?.identity.name ?? title
    }
    
    public var canRevealSelfIdentity: Bool {
        !hasRevealedSelfIdentity && kind == .twoWay
    }
    
    private var hasRevealedSelfIdentity: Bool {
        selfMember?.identity.isKnown ?? false
    }
    
    public var recipientPointers: [Pointer] {
        guard members.count == 2 else {
            return []
        }
        
        let recipient = members.first { !$0.isSelf }
        return recipient?.pointers ?? []
    }
    
    public var unreadCount: Int {
        selfMember?.numUnread ?? 0
    }
    
    public var isMuted: Bool {
        selfMember?.isMuted ?? false
    }
    
    public var isSubscribed: Bool {
        selfMember?.isSubscribed ?? false
    }
    
    public var oldestMessage: Message? {
        messages.first
    }
    
    public var newestMessage: Message? {
        messages.last
    }
    
    // MARK: - Init -
    
    public init(id: ID, cursor: ID, kind: Kind, title: String, canMute: Bool, canUnsubscribe: Bool, members: [Member], messages: [Message]) {
        self.id = id
        self.cursor = cursor
        self.kind = kind
        self.title = title
        self.canMute = canMute
        self.canUnsubscribe = canUnsubscribe
        self.members = members
        self.messages = messages
    }
    
    // MARK: - State -
    
    public func resetUnreadCount() {
        updatingSelf { member in
            member.numUnread = 0
        }
    }
    
    public func setMuted(_ muted: Bool) {
        updatingSelf { member in
            member.isMuted = muted
        }
    }
    
    public func setSubscribed(_ subscribed: Bool) {
        updatingSelf { member in
            member.isSubscribed = subscribed
        }
    }
    
    private func updatingSelf(block: (inout Member) -> Void) {
        if let index = members.firstIndex(where: { $0.isSelf }) {
            block(&members[index])
        }
    }
    
    // MARK: - Pointers -
    
    public func setPointer(_ pointer: Pointer) {
        guard let memberIndex = members.firstIndex(where: { $0.id == pointer.memberID }) else {
            return
        }
        
        var memberToUpdate = members[memberIndex]
        
        guard let index = memberToUpdate.pointers.firstIndex(where: { $0.kind == pointer.kind }) else {
            return
        }
        
        memberToUpdate.pointers[index] = pointer
        members[memberIndex] = memberToUpdate
        
        objectWillChange.send()
    }
    
    // MARK: - Messages -
    
    public func isMessageFromSelf(_ message: Message) -> Bool {
        // For notification messages the sender
        // isn't self but we want it to appear
        // on the 'self' side
        message.senderID == selfMember?.id || !message.isContentReceived()
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
        self.messages = messages.map {
            var mappedMessage = $0
            mappedMessage.contents = $0.contents.map {
                if case .identityRevealed(let memberID, let identity) = $0 {
                    let direction: Chat.Content.Direction = memberID == selfMember?.id ? .fromSelf : .fromOther
                    return .identity(direction, identity)
                } else {
                    return $0
                }
            }
            return mappedMessage
        }
    }
    
    public func latestMessage() -> Message? {
        messages.last // Order is ascending
    }
    
    public func popLast() -> Message? {
        messages.popLast()
    }
    
    @discardableResult
    public func update(from chat: Chat) -> Bool {
        guard chat.id == id else {
            return false
        }
        
        cursor = chat.cursor
        title = chat.title
        kind = chat.kind
        canMute = chat.canMute
        canUnsubscribe = chat.canUnsubscribe
        members = chat.members
        messages = chat.messages
        
        return true
    }
}

extension Chat: Hashable, Equatable {
    nonisolated
    public static func == (lhs: Chat, rhs: Chat) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension Chat {
    public enum Kind: Int {
        case unknown
        case notification
        case twoWay
    }
}

extension Chat {
    public enum Verb: Equatable, Hashable {
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
            
extension Chat {
    public enum MessageDirection {
        case sent
        case received
    }
}

// MARK: - Proto -

extension Chat {
    convenience init(_ proto: Code_Chat_V2_ChatMetadata) {
        self.init(
            id: .init(data: proto.chatID.value),
            cursor: .init(data: proto.cursor.value),
            kind: Kind(rawValue: proto.type.rawValue) ?? .unknown,
            title: proto.title,
            canMute: proto.canMute,
            canUnsubscribe: proto.canUnsubscribe,
            members: proto.members.map { .init($0) },
            messages: []
        )
    }
}

// MARK: - Description -

extension Chat: CustomDebugStringConvertible, CustomStringConvertible {
    public var description: String {
        let messages = messages.map { message in
            "\(message.date) \(message.id.data.hexEncodedString())"
        }.joined(separator: "\n")
        
        return "\(id.data.hexEncodedString()) (\(String(describing: title))\n\(messages)"
    }
    
    public var debugDescription: String {
        description
    }
}
