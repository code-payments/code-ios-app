//
//  ConversationIdentifiers.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

/// Identifier for a conversation, backed by the server's 32-byte ChatId.
public struct ConversationID: Hashable, Sendable, CustomStringConvertible {

    public let data: Data

    public init(data: Data) {
        self.data = data
    }

    public init(_ proto: Flipcash_Common_V1_ChatId) {
        self.data = proto.value
    }

    /// Decodes the base64url form the server uses in `/chat/{chatId}` deep
    /// links. Fails unless the decoded value is the exact 32-byte ChatId
    /// length. Accepts both padded and unpadded input.
    public init?(base64URLEncoded string: String) {
        let base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padded = base64.padding(
            toLength: (base64.count + 3) / 4 * 4,
            withPad: "=",
            startingAt: 0
        )
        guard let data = Data(base64Encoded: padded), data.count == 32 else {
            return nil
        }
        self.data = data
    }

    public var proto: Flipcash_Common_V1_ChatId {
        .with { $0.value = data }
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

    /// Placeholder id for an optimistic message the server hasn't assigned a real id to yet. Never used
    /// for ordering or lookup — pending rows are keyed by their client id, anchor, and send sequence —
    /// so it only fills the non-optional `id` field until reconciliation replaces it with the real id.
    public static let unassigned = MessageID(value: .max)

    public init(_ proto: Flipcash_Messaging_V1_MessageId) {
        self.value = proto.value
    }

    public var proto: Flipcash_Messaging_V1_MessageId {
        .with { $0.value = value }
    }

    /// The opaque paging cursor for fetching messages older than this one: the
    /// gapless `value` as 8 big-endian bytes, matching the server's
    /// `PageTokenFromID`. Passed as `QueryOptions.pagingToken` with `order: .desc`
    /// to resume strictly older than this message.
    public var pagingToken: Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    public static func < (lhs: MessageID, rhs: MessageID) -> Bool {
        lhs.value < rhs.value
    }

    public var description: String {
        "\(value)"
    }
}
