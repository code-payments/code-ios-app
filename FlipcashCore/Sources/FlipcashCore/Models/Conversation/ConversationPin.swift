//
//  ConversationPin.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import SwiftProtobuf

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

    /// The `chat.v1.Pin` bytes this pin was read from, kept so the cache can store the pin whole:
    /// the pinned message may not be in the local message store. Not part of equality.
    private let wireBytes: Data?

    public init(messageID: MessageID, pinnedBy: UserID?, pinnedAt: Date?, message: ConversationMessage?) {
        self.init(messageID: messageID, pinnedBy: pinnedBy, pinnedAt: pinnedAt, message: message, wireBytes: nil)
    }

    private init(messageID: MessageID, pinnedBy: UserID?, pinnedAt: Date?, message: ConversationMessage?, wireBytes: Data?) {
        self.messageID = messageID
        self.pinnedBy = pinnedBy
        self.pinnedAt = pinnedAt
        self.message = message
        self.wireBytes = wireBytes
    }

    public static func == (lhs: ConversationPin, rhs: ConversationPin) -> Bool {
        lhs.messageID == rhs.messageID && lhs.pinnedBy == rhs.pinnedBy && lhs.pinnedAt == rhs.pinnedAt && lhs.message == rhs.message
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(messageID)
        hasher.combine(pinnedBy)
        hasher.combine(pinnedAt)
        hasher.combine(message)
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
            message: proto.hasMessage ? ConversationMessage(proto.message) : nil,
            wireBytes: try? proto.serializedData()
        )
    }

    /// Restores a pin from the bytes ``serializedBytes`` produced; `nil` when they do not decode.
    public init?(serializedBytes: Data) {
        guard let proto = try? Flipcash_Chat_V1_Pin(serializedBytes: serializedBytes) else { return nil }
        self.init(proto)
    }

    /// The serialized `chat.v1.Pin`, for the cache. A pin built without a proto carries only its ids
    /// and times; the message is left out.
    public var serializedBytes: Data? {
        if let wireBytes { return wireBytes }
        let proto = Flipcash_Chat_V1_Pin.with {
            $0.messageID = .with { $0.value = messageID.value }
            if let pinnedBy {
                $0.pinnedBy = .with { $0.value = withUnsafeBytes(of: pinnedBy.uuid) { Data($0) } }
            }
            if let pinnedAt { $0.pinnedAt = .init(date: pinnedAt) }
        }
        return try? proto.serializedData()
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
