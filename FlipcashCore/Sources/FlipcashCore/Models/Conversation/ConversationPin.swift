//
//  ConversationPin.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

/// One message pinned in a chat. See `chat.v1.Pin`.
public struct ConversationPin: Hashable, Sendable {

    public let messageID: MessageID

    /// Who pinned the message; `nil` when the id does not parse.
    public let pinnedBy: UserID?

    /// When the message was pinned; `nil` when the server left it unset.
    public let pinnedAt: Date?

    /// The pinned message, which may be redacted per the read's view mode. `nil` when the message
    /// does not map to a displayable one.
    public let message: ConversationMessage?

    public init(messageID: MessageID, pinnedBy: UserID?, pinnedAt: Date?, message: ConversationMessage?) {
        self.messageID = messageID
        self.pinnedBy = pinnedBy
        self.pinnedAt = pinnedAt
        self.message = message
    }

    /// Whether the pinned message was deleted after it was pinned. The server keeps such a pin as a
    /// tombstone; clients don't show it.
    public var isDeleted: Bool {
        message?.isDeleted ?? false
    }
}

extension ConversationPin {
    public init(_ proto: Flipcash_Chat_V1_Pin) {
        self.init(
            messageID: MessageID(proto.messageID),
            pinnedBy: proto.hasPinnedBy ? try? UUID(data: proto.pinnedBy.value) : nil,
            pinnedAt: proto.hasPinnedAt ? proto.pinnedAt.date : nil,
            message: proto.hasMessage ? ConversationMessage(proto.message) : nil
        )
    }
}

/// Summary of a chat's pins without holding the list. See `chat.v1.PinSummary`.
public struct ConversationPinSummary: Hashable, Sendable {

    /// The most recently pinned message; `nil` when nothing is pinned.
    public let latest: ConversationPin?

    /// How many messages are currently pinned.
    public let count: UInt32

    /// Advanced by exactly one on every pin and unpin. Compared like
    /// ``ConversationRosterSummary/version``: keep the greater value and drop the rest.
    public let version: UInt64

    public init(latest: ConversationPin?, count: UInt32, version: UInt64) {
        self.latest = latest
        self.count = count
        self.version = version
    }
}

extension ConversationPinSummary {
    public init(_ proto: Flipcash_Chat_V1_PinSummary) {
        self.init(
            latest: proto.hasLatest ? ConversationPin(proto.latest) : nil,
            count: proto.count,
            version: proto.version
        )
    }
}

/// What a `PinsChanged` update did to the pins. See `chat.v1.MetadataUpdate.PinsChanged`.
public enum ConversationPinChange: Hashable, Sendable {
    case pinned(ConversationPin)
    case unpinned(MessageID)
}

/// One page of a chat's pins, most recently pinned first. See `chat.v1.GetPinnedMessagesResponse`.
public struct ConversationPinsPage: Sendable {
    public let pins: [ConversationPin]

    /// The chat's pin summary as of the read.
    public let summary: ConversationPinSummary?

    /// The cursor for the next page; pass it back to continue.
    public let pagingToken: Data

    public let hasMore: Bool

    public init(pins: [ConversationPin], summary: ConversationPinSummary?, pagingToken: Data, hasMore: Bool) {
        self.pins = pins
        self.summary = summary
        self.pagingToken = pagingToken
        self.hasMore = hasMore
    }
}
