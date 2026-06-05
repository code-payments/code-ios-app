//
//  Conversation.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

/// A direct-message chat between two members. The server orders the feed by
/// `lastActivity` (most recent first); the client maintains that sort locally
/// from the event stream.
public struct Conversation: Identifiable, Hashable, Sendable {

    public let id: ChatID
    public var members: [ChatMember]
    public var lastMessage: ChatMessage?
    public var lastActivity: Date

    public init(id: ChatID, members: [ChatMember], lastMessage: ChatMessage?, lastActivity: Date) {
        self.id = id
        self.members = members
        self.lastMessage = lastMessage
        self.lastActivity = lastActivity
    }
}

extension Conversation {
    public init(_ proto: Flipcash_Chat_V1_Metadata) {
        self.id = ChatID(proto.chatID)
        self.members = proto.members.map(ChatMember.init)
        self.lastMessage = proto.hasLastMessage ? ChatMessage(proto.lastMessage) : nil
        self.lastActivity = proto.hasLastActivity ? proto.lastActivity.date : .distantPast
    }

    /// The member that isn't the signed-in user, used to title the conversation.
    public func counterpart(excluding selfUserID: UserID?) -> ChatMember? {
        members.first { $0.userID != selfUserID } ?? members.first
    }
}

/// A participant in a chat. The server does not yet hydrate member profiles, so
/// `displayName` is typically empty and resolved from local contacts.
public struct ChatMember: Hashable, Sendable, Identifiable {

    public let userID: UserID?
    public var displayName: String

    public var id: String { userID?.uuidString ?? displayName }

    public init(userID: UserID?, displayName: String) {
        self.userID = userID
        self.displayName = displayName
    }
}

extension ChatMember {
    public init(_ proto: Flipcash_Chat_V1_Member) {
        self.userID = try? UUID(data: proto.userID.value)
        self.displayName = proto.userProfile.displayName
    }
}
