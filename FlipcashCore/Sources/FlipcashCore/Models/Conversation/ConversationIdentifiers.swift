//
//  ConversationIdentifiers.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

/// Identifier for a conversation, backed by the server's 32-byte ChatId.
public struct ConversationID: Hashable, Sendable, Comparable, CustomStringConvertible {

    public let data: Data

    public init(data: Data) {
        self.data = data
    }

    public init(_ proto: Flipcash_Common_V1_ChatId) {
        self.data = proto.value
    }

    public var proto: Flipcash_Common_V1_ChatId {
        .with { $0.value = data }
    }

    public static func < (lhs: ConversationID, rhs: ConversationID) -> Bool {
        lhs.data.lexicographicallyPrecedes(rhs.data)
    }

    public var description: String {
        data.hexString()
    }
}

/// Per-conversation, gapless, server-assigned message sequence number. Doubles as
/// the sort key and pagination cursor.
public struct MessageID: Hashable, Sendable, Comparable, CustomStringConvertible {

    public let value: UInt64

    public init(value: UInt64) {
        self.value = value
    }

    public init(_ proto: Flipcash_Messaging_V1_MessageId) {
        self.value = proto.value
    }

    public var proto: Flipcash_Messaging_V1_MessageId {
        .with { $0.value = value }
    }

    public static func < (lhs: MessageID, rhs: MessageID) -> Bool {
        lhs.value < rhs.value
    }

    public var description: String {
        "\(value)"
    }
}
