//
//  ConversationMessage.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

/// A single message within a conversation. PoC scope: text content only.
public struct ConversationMessage: Identifiable, Hashable, Sendable {

    public let id: MessageID
    public let senderID: UserID?
    public let text: String
    public let date: Date
    public let unreadSeq: UInt64

    public init(id: MessageID, senderID: UserID?, text: String, date: Date, unreadSeq: UInt64) {
        self.id = id
        self.senderID = senderID
        self.text = text
        self.date = date
        self.unreadSeq = unreadSeq
    }
}

extension ConversationMessage {
    /// Builds a message from its proto, returning nil for non-text content —
    /// the only content type the PoC renders.
    public init?(_ proto: Flipcash_Messaging_V1_Message) {
        guard case .text(let textContent)? = proto.content.first?.type else {
            return nil
        }

        self.id = MessageID(proto.messageID)
        self.senderID = try? UUID(data: proto.senderID.value)
        self.text = textContent.text
        self.date = proto.hasTs ? proto.ts.date : .now
        self.unreadSeq = proto.unreadSeq
    }
}
