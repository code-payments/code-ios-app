//
//  ConversationMessage.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

/// Delivery state of an outgoing message. `.sent` is the only state a message loaded from the
/// server, the stream, or the local cache can have; `.sending`/`.failed` exist only for an
/// optimistic message in flight on this device this session.
public enum SendStatus: Sendable, Hashable {
    case sent
    case sending
    case failed
}

/// A single message within a conversation.
public struct ConversationMessage: Identifiable, Hashable, Sendable {

    /// The message payload. Cash messages are created server-side when a
    /// payment intent carries chat metadata — clients never send them directly.
    /// `deleted` is a tombstone: the server (a moderation removal, or another
    /// client's delete) replaced the content, so the row is retained for gapless
    /// ordering but rendered nowhere.
    public enum Content: Hashable, Sendable {
        case text(String)
        case cash(ExchangedFiat)
        case deleted
    }

    public let id: MessageID
    public let senderID: UserID?
    public let content: Content
    public let date: Date
    public let unreadSeq: UInt64
    /// The event-log version at which this message reached its current state,
    /// advancing on every send/edit/delete. The store applies last-writer-wins
    /// by this value, so a stale copy (from any delivery path) never overwrites a
    /// newer one. Zero for optimistic sends and legacy cache rows that predate
    /// the event log — a real server copy (always `>= 1`) out-versions them.
    public let eventSequence: UInt64
    /// Delivery state. `.sent` for every server/cache message; `.sending`/`.failed` only for an
    /// in-flight optimistic message.
    public var status: SendStatus
    /// The id the client minted for this send, reused across retries (the server is idempotent on
    /// it). Set only for messages that originated optimistically on this device; nil for everything
    /// loaded from the server, the stream, or the cache. Mutable so the store can carry it onto the
    /// confirmed server copy during reconciliation without rebuilding the whole value.
    public var clientMessageID: UUID?

    public init(
        id: MessageID,
        senderID: UserID?,
        content: Content,
        date: Date,
        unreadSeq: UInt64,
        eventSequence: UInt64 = 0,
        status: SendStatus = .sent,
        clientMessageID: UUID? = nil
    ) {
        self.id = id
        self.senderID = senderID
        self.content = content
        self.date = date
        self.unreadSeq = unreadSeq
        self.eventSequence = eventSequence
        self.status = status
        self.clientMessageID = clientMessageID
    }
}

extension ConversationMessage {
    /// Identity used by the transcript diff: the client id while the server id is unknown (and
    /// preserved after reconciliation), so a row keeps its identity across sending → sent and never
    /// re-inserts. Falls back to the server id.
    public var stableID: String {
        clientMessageID?.uuidString ?? "\(id.value)"
    }
}

extension ConversationMessage {
    /// `true` when this message was sent by the given user.
    public func isFromSelf(_ selfUserID: UserID) -> Bool {
        senderID == selfUserID
    }
}

extension ConversationMessage {
    /// Builds a message from its proto, returning nil for content the client
    /// can't represent (unknown type, or a cash amount that fails to parse). A
    /// deleted message materializes as a `.deleted` tombstone — never nil — so
    /// it converges the same way across the stream, `GetMessages`, and `GetDelta`
    /// and can't leave the pre-delete content on screen.
    public init?(_ proto: Flipcash_Messaging_V1_Message) {
        switch proto.content.first?.type {
        case .text(let textContent):
            self.content = .text(textContent.text)
        case .cash(let cashContent):
            guard let amount = try? ExchangedFiat(cashContent.amount) else {
                return nil
            }
            self.content = .cash(amount)
        case .deleted:
            self.content = .deleted
        case .reply, .media, .system, .none:
            return nil
        }

        self.id = MessageID(proto.messageID)
        self.senderID = try? UUID(data: proto.senderID.value)
        self.date = proto.hasTs ? proto.ts.date : .now
        self.unreadSeq = proto.unreadSeq
        self.eventSequence = proto.eventSequence
        self.status = .sent
        self.clientMessageID = nil
    }
}
