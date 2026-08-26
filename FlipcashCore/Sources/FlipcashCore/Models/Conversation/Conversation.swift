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
    public let type: ConversationType
    /// Whether the server has hidden this conversation from the feed because the counterpart is on the owner's blocklist.
    public var isHidden: Bool
    /// The server-set title. Only populated for group chats; `nil` for DMs,
    /// where the counterpart's name is used instead.
    public var title: String?

    /// The newest event-log sequence the server holds for this chat, as reported
    /// by the feed. Compared against the locally-applied catch-up cursor to tell
    /// a transcript that lags the server from one that is current.
    ///
    /// Server truth valid only at fetch time, so it is deliberately not cached:
    /// a conversation restored from the local database reports `0`, meaning
    /// "unknown", not "empty".
    public var latestEventSequence: UInt64

    public init(id: ConversationID, members: [ConversationMember], lastMessage: ConversationMessage?, lastActivity: Date, type: ConversationType = .contactDm, isHidden: Bool = false, title: String? = nil, latestEventSequence: UInt64 = 0) {
        self.id = id
        self.members = members
        self.lastMessage = lastMessage
        self.lastActivity = lastActivity
        self.type = type
        self.isHidden = isHidden
        self.title = title
        self.latestEventSequence = latestEventSequence
    }
}

/// The kind of conversation, used to scope the feed. Raw values match the
/// proto's `ChatType` and are what the local cache stores.
public enum ConversationType: Int, Sendable {
    case contactDm = 1
    case tipDm = 2
    case group = 3
}

extension ConversationType {
    var proto: Flipcash_Chat_V1_ChatType {
        switch self {
        case .contactDm: .contactDm
        case .tipDm:     .tipDm
        case .group:     .group
        }
    }

    /// Unknown chat types map to `.contactDm`, mirroring the server's
    /// legacy-client contract for the DM feed.
    init(_ proto: Flipcash_Chat_V1_ChatType) {
        switch proto {
        case .tipDm:
            self = .tipDm
        case .group:
            self = .group
        case .contactDm, .unknown, .UNRECOGNIZED:
            self = .contactDm
        }
    }
}

extension Conversation {
    public init(_ proto: Flipcash_Chat_V1_Metadata) {
        self.id = ConversationID(proto.chatID)
        self.members = proto.members.map(ConversationMember.init)
        self.lastMessage = proto.hasLastMessage ? ConversationMessage(proto.lastMessage) : nil
        self.lastActivity = proto.hasLastActivity ? proto.lastActivity.date : .distantPast
        self.type = ConversationType(proto.type)
        self.isHidden = proto.isHidden
        // Proto represents an unset title as an empty string; normalize to nil so
        // DMs (which never carry a title) and untitled groups behave the same.
        self.title = proto.title.isEmpty ? nil : proto.title
        self.latestEventSequence = proto.latestEventSequence
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
    /// The blobs backing this member's profile picture, when they have one.
    /// The renditions authorize through the member's profile access context.
    public var profilePicture: ProfilePicture?
    /// The member's Flipcash handle, when they have claimed one. Carried on the
    /// same `profile.v1.UserProfile` the member embeds, so it arrives with the
    /// conversation and needs no separate profile fetch.
    public var username: Username?

    public var id: String { userID?.uuidString ?? displayName }

    public init(userID: UserID?, displayName: String, phoneE164: String? = nil, readPointer: MessageID? = nil, readPointerTimestamp: Date? = nil, profilePicture: ProfilePicture? = nil, username: Username? = nil) {
        self.userID = userID
        self.displayName = displayName
        self.phoneE164 = phoneE164
        self.readPointer = readPointer
        self.readPointerTimestamp = readPointerTimestamp
        self.profilePicture = profilePicture
        self.username = username
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
        self.profilePicture = proto.userProfile.hasProfilePicture
            ? ProfilePicture(proto.userProfile.profilePicture)
            : nil
        self.username = proto.userProfile.hasUsername
            ? Username(proto.userProfile.username)
            : nil
    }
}
