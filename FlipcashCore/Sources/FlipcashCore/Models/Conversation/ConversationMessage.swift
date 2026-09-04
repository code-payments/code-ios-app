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

/// How a cash message was delivered. `.sent` is the wire default and the fallback for any
/// message that predates the field or carries an unrecognized action.
public enum CashAction: Sendable, Hashable {
    case sent
    case tipped
}

/// A single message within a conversation.
public struct ConversationMessage: Identifiable, Hashable, Sendable {

    /// Who removed a message and when — the tombstone's payload. `deletedBy` is `nil` when the
    /// server does not attribute the deletion (a moderation removal, for instance).
    public struct Deletion: Hashable, Sendable {
        public let deletedBy: UserID?
        public let deletedAt: Date

        public init(deletedBy: UserID?, deletedAt: Date) {
            self.deletedBy = deletedBy
            self.deletedAt = deletedAt
        }
    }

    /// The message payload. Cash messages are created server-side when a
    /// payment intent carries chat metadata — clients never send them directly.
    /// `deleted` is a tombstone: the sender, another client, or a moderation
    /// removal replaced the content, so the row is retained for gapless ordering
    /// and rendered per the conversation's `DeletedMessagePresentation`.
    public enum Content: Hashable, Sendable {
        case text(String)
        case cash(ExchangedFiat)
        case deleted(Deletion)
    }

    public let id: MessageID
    public let senderID: UserID?
    public let content: Content
    /// How a `.cash` message was delivered (sent vs. tipped); `nil` for non-cash content.
    public let cashAction: CashAction?
    public let date: Date
    public let unreadSeq: UInt64
    /// The event-log version at which this message reached its current state,
    /// advancing on every send/edit/delete. The store applies last-writer-wins
    /// by this value, so a stale copy (from any delivery path) never overwrites a
    /// newer one. Zero for optimistic sends and legacy cache rows that predate
    /// the event log — a real server copy (always `>= 1`) out-versions them.
    public let eventSequence: UInt64
    /// When the sender last edited this message, or `nil` if it has never been edited.
    public let lastEditedTs: Date?
    /// The message this one replies to, or `nil` when it replies to nothing. A reply is a
    /// decoration on a text message rather than a content kind of its own: the wire nests the
    /// body inside `ReplyContent`, and the initializer below unwraps it so every `case .text`
    /// path — link detection, the transcript mapper, the bubble, edit — sees the shape it
    /// always saw.
    public let repliedTo: MessageID?
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
        cashAction: CashAction? = nil,
        date: Date,
        unreadSeq: UInt64,
        eventSequence: UInt64 = 0,
        lastEditedTs: Date? = nil,
        repliedTo: MessageID? = nil,
        status: SendStatus = .sent,
        clientMessageID: UUID? = nil
    ) {
        self.id = id
        self.senderID = senderID
        self.content = content
        self.cashAction = cashAction
        self.date = date
        self.unreadSeq = unreadSeq
        self.eventSequence = eventSequence
        self.lastEditedTs = lastEditedTs
        self.repliedTo = repliedTo
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

    /// Whether this message has been replaced by a tombstone.
    public var isDeleted: Bool {
        if case .deleted = content { true } else { false }
    }

    /// A copy carrying different content. Identity, ordering, and delivery status are preserved —
    /// this exists for the optimistic mutation overlay, which changes what a message says and
    /// nothing else about where it sits.
    public func replacingContent(_ content: Content, lastEditedTs: Date?) -> ConversationMessage {
        ConversationMessage(
            id: id,
            senderID: senderID,
            content: content,
            cashAction: cashAction,
            date: date,
            unreadSeq: unreadSeq,
            eventSequence: eventSequence,
            lastEditedTs: lastEditedTs,
            repliedTo: repliedTo,
            status: status,
            clientMessageID: clientMessageID
        )
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
        let repliedTo: MessageID?
        switch proto.content.first?.type {
        case .text(let textContent):
            self.content = .text(textContent.text)
            self.cashAction = nil
            repliedTo = nil
        case .cash(let cashContent):
            guard let amount = try? ExchangedFiat(cashContent.amount) else {
                return nil
            }
            self.content = .cash(amount)
            // Unrecognized verbs fall back to `.sent`, per the proto contract.
            self.cashAction = cashContent.verb == .tipped ? .tipped : .sent
            repliedTo = nil
        case .deleted(let deletedContent):
            self.content = .deleted(
                Deletion(
                    deletedBy: deletedContent.hasDeletedBy ? try? UUID(data: deletedContent.deletedBy.value) : nil,
                    deletedAt: deletedContent.hasDeletedTs ? deletedContent.deletedTs.date : proto.ts.date
                )
            )
            self.cashAction = nil
            repliedTo = nil
        case .reply(let replyContent):
            // The wire nests the body one level down; unwrap it so the message is a text message
            // that happens to point at another, not a second shape every `case .text` must learn.
            // `content` is repeated on the wire but carries exactly one entry in practice — a
            // reply with nothing inside has no body to draw, so it is dropped like any other
            // content the client cannot represent.
            guard case .text(let textContent)? = replyContent.content.first?.type else {
                return nil
            }
            self.content = .text(textContent.text)
            self.cashAction = nil
            repliedTo = replyContent.hasRepliedMessageID ? MessageID(replyContent.repliedMessageID) : nil
        case .media, .system, .none:
            return nil
        }

        self.id = MessageID(proto.messageID)
        self.senderID = try? UUID(data: proto.senderID.value)
        self.date = proto.hasTs ? proto.ts.date : .now
        self.unreadSeq = proto.unreadSeq
        self.eventSequence = proto.eventSequence
        self.lastEditedTs = proto.hasLastEditedTs ? proto.lastEditedTs.date : nil
        self.repliedTo = repliedTo
        self.status = .sent
        self.clientMessageID = nil
    }
}
