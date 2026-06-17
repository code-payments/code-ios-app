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

    /// The counterpart's READ watermark and the time they last advanced it,
    /// for the "Read" receipt under the user's latest sent message. Resolves
    /// the other member directly (no fallback to `members.first`) so a
    /// malformed single-member conversation yields `nil` rather than a false
    /// self-receipt. `nil` until the counterpart has read anything.
    public func counterpartReadReceipt(excluding selfUserID: UserID?) -> ReadReceiptState? {
        guard let member = members.first(where: { $0.userID != selfUserID }),
              let pointer = member.readPointer else {
            return nil
        }
        return ReadReceiptState(pointer: pointer, date: member.readPointerTimestamp)
    }

    /// Whether the latest message postdates the signed-in user's READ
    /// watermark. A missing watermark means nothing has been read yet, so any
    /// message counts as unread.
    public func hasUnread(for selfUserID: UserID?) -> Bool {
        guard let lastMessage else { return false }
        guard let read = selfReadPointer(for: selfUserID) else { return true }
        return read < lastMessage.id
    }
}

/// A member's READ watermark paired with the time they last advanced it. Drives
/// the "Read 3:42 PM" receipt. `date` is `nil` only when the server omits the
/// pointer timestamp.
public struct ReadReceiptState: Equatable, Sendable {
    public let pointer: MessageID
    public let date: Date?

    public init(pointer: MessageID, date: Date?) {
        self.pointer = pointer
        self.date = date
    }
}

/// A participant in a conversation. `displayName` is the member's profile name
/// from the feed payload; it may be empty when the user hasn't set one.
public struct ConversationMember: Hashable, Sendable, Identifiable {

    public let userID: UserID?
    public var displayName: String
    /// The member's E.164 phone number, when the server shared it. For DM chats
    /// the server populates this per member so each party can resolve the other
    /// to a contact; `nil` for group chats and when no number is on file.
    public var phoneE164: String?
    /// This member's READ watermark: every message at or before it is read.
    /// `nil` until the server reports one in the feed/stream.
    public var readPointer: MessageID?
    /// When this member last advanced their READ watermark, for the read
    /// receipt. `nil` until the server reports a pointer with a timestamp.
    public var readPointerTimestamp: Date?

    public var id: String { userID?.uuidString ?? displayName }

    public init(userID: UserID?, displayName: String, phoneE164: String? = nil, readPointer: MessageID? = nil, readPointerTimestamp: Date? = nil) {
        self.userID = userID
        self.displayName = displayName
        self.phoneE164 = phoneE164
        self.readPointer = readPointer
        self.readPointerTimestamp = readPointerTimestamp
    }

    /// The member's phone number formatted for display, used as a conversation
    /// title fallback before the generic name. National format, falling back to
    /// the raw E.164 when it can't be parsed.
    public var formattedPhoneNumber: String? {
        guard let phoneE164, !phoneE164.isEmpty else { return nil }
        return Phone(phoneE164)?.national ?? phoneE164
    }
}

extension ConversationMember {
    public init(_ proto: Flipcash_Chat_V1_Member) {
        self.userID = try? UUID(data: proto.userID.value)
        self.displayName = proto.userProfile.displayName
        self.phoneE164 = proto.userProfile.phoneNumber.value.isEmpty ? nil : proto.userProfile.phoneNumber.value

        var read: MessageID?
        var readAt: Date?
        for pointer in proto.pointers {
            switch pointer.type {
            case .read:
                read = MessageID(pointer.value)
                readAt = pointer.hasTs ? pointer.ts.date : nil
            case .delivered, .sent, .unknown, .UNRECOGNIZED:
                break
            }
        }
        self.readPointer = read
        self.readPointerTimestamp = readAt
    }
}
