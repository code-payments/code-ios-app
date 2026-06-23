//
//  ConversationMessage.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

/// A single message within a conversation.
public struct ConversationMessage: Identifiable, Hashable, Sendable {

    /// The message payload. Cash messages are created server-side when a
    /// payment intent carries chat metadata — clients never send them directly.
    public enum Content: Hashable, Sendable {
        case text(String)
        case cash(ExchangedFiat)
    }

    public let id: MessageID
    public let senderID: UserID?
    public let content: Content
    public let date: Date
    public let unreadSeq: UInt64

    public init(id: MessageID, senderID: UserID?, content: Content, date: Date, unreadSeq: UInt64) {
        self.id = id
        self.senderID = senderID
        self.content = content
        self.date = date
        self.unreadSeq = unreadSeq
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
    /// can't represent (unknown type, or a cash amount that fails to parse).
    public init?(_ proto: Flipcash_Messaging_V1_Message) {
        switch proto.content.first?.type {
        case .text(let textContent):
            self.content = .text(textContent.text)
        case .cash(let cashContent):
            guard let amount = try? ExchangedFiat(cashContent.amount) else {
                return nil
            }
            self.content = .cash(amount)
        case .none:
            return nil
        }

        self.id = MessageID(proto.messageID)
        self.senderID = try? UUID(data: proto.senderID.value)
        self.date = proto.hasTs ? proto.ts.date : .now
        self.unreadSeq = proto.unreadSeq
    }
}
