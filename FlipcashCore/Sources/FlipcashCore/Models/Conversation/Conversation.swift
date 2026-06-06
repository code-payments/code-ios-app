//
//  Conversation.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

/// A direct-message conversation between two members. The server orders the feed
/// by `lastActivity` (most recent first); the client maintains that sort locally
/// from the event stream.
public struct Conversation: Identifiable, Hashable, Sendable {

    public let id: ConversationID
    public var members: [ConversationMember]
    public var lastMessage: ConversationMessage?
    public var lastActivity: Date

    public init(id: ConversationID, members: [ConversationMember], lastMessage: ConversationMessage?, lastActivity: Date) {
        self.id = id
        self.members = members
        self.lastMessage = lastMessage
        self.lastActivity = lastActivity
    }
}

extension Conversation {
    public init(_ proto: Flipcash_Chat_V1_Metadata) {
        self.id = ConversationID(proto.chatID)
        self.members = proto.members.map(ConversationMember.init)
        self.lastMessage = proto.hasLastMessage ? ConversationMessage(proto.lastMessage) : nil
        self.lastActivity = proto.hasLastActivity ? proto.lastActivity.date : .distantPast
    }

    /// The member that isn't the signed-in user, used to title the conversation.
    public func counterpart(excluding selfUserID: UserID?) -> ConversationMember? {
        members.first { $0.userID != selfUserID } ?? members.first
    }

    /// The signed-in user's READ watermark in this conversation, if reported.
    public func selfReadPointer(for selfUserID: UserID?) -> MessageID? {
        members.first { $0.userID == selfUserID }?.readPointer
    }
}

/// A participant in a conversation. `displayName` is the member's profile name
/// from the feed payload; it may be empty when the user hasn't set one.
public struct ConversationMember: Hashable, Sendable, Identifiable {

    public let userID: UserID?
    public var displayName: String
    /// This member's READ watermark: every message at or before it is read.
    /// `nil` until the server reports one in the feed/stream.
    public var readPointer: MessageID?

    public var id: String { userID?.uuidString ?? displayName }

    public init(userID: UserID?, displayName: String, readPointer: MessageID? = nil) {
        self.userID = userID
        self.displayName = displayName
        self.readPointer = readPointer
    }
}

extension ConversationMember {
    public init(_ proto: Flipcash_Chat_V1_Member) {
        self.userID = try? UUID(data: proto.userID.value)
        self.displayName = proto.userProfile.displayName

        var read: MessageID?
        for pointer in proto.pointers {
            switch pointer.type {
            case .read:
                read = MessageID(pointer.value)
            case .delivered, .sent, .unknown, .UNRECOGNIZED:
                break
            }
        }
        self.readPointer = read
    }
}
