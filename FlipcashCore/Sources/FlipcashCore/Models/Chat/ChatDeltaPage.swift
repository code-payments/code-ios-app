//
//  ChatDeltaPage.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// One capped `GetDelta` read: the messages changed since the request's cursor, the chat's head,
/// and whether the stream ended on its own rather than at the cap.
public struct ChatDeltaPage: Sendable, Equatable {
    public let messages: [ConversationMessage]
    public let head: UInt64
    public let isComplete: Bool

    public init(messages: [ConversationMessage], head: UInt64, isComplete: Bool) {
        self.messages = messages
        self.head = head
        self.isComplete = isComplete
    }
}

/// What a notification extension writes to the shared store for one push.
public struct ChatStoreWrite: Equatable, Sendable {
    /// One row per message, newest version of each.
    public let messages: [ConversationMessage]
    /// The catch-up cursor to persist, or 0 to leave the stored one alone.
    public let cursor: UInt64

    /// Combines the preview the extension fetched with its delta. The cursor moves to the head only
    /// when the delta ran to its end: then the store holds every event through the head, and the
    /// app's next catch-up has nothing to fetch. A preview alone, or a delta cut off at its cap,
    /// can leave a gap, so the cursor stays where the app left it.
    public init(preview: [ConversationMessage], delta: ChatDeltaPage?) {
        var newest: [MessageID: ConversationMessage] = [:]
        var order: [MessageID] = []
        for message in preview + (delta?.messages ?? []) {
            if let stored = newest[message.id] {
                if message.eventSequence > stored.eventSequence { newest[message.id] = message }
            } else {
                newest[message.id] = message
                order.append(message.id)
            }
        }
        self.messages = order.compactMap { newest[$0] }
        self.cursor = delta.map { $0.isComplete ? $0.head : 0 } ?? 0
    }
}
