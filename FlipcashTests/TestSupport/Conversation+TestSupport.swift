//
//  Conversation+TestSupport.swift
//  FlipcashTests
//

import Foundation
import FlipcashCore

extension ConversationID {
    /// A deterministic 32-byte ChatId filled with `byte`.
    static func test(_ byte: UInt8) -> ConversationID {
        ConversationID(data: Data(repeating: byte, count: 32))
    }
}

extension ConversationStreamEvent {
    /// A live `.chatEvents` update carrying `messages` as one contiguous run of `.sent` mutations,
    /// as the server delivers a send. The run is sequenced from zero, so it lands on a conversation
    /// whose frontier the test has not seeded.
    static func sent(_ messages: [ConversationMessage], in conversationID: ConversationID) -> ConversationStreamEvent {
        .chatEvents(conversationID: conversationID, events: [
            DecodedChatEvent(
                sequence: UInt64(messages.count),
                count: UInt64(messages.count),
                mutations: messages.map { .sent($0) }
            )
        ])
    }
}
