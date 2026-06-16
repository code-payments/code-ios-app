//
//  ConversationStore.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Pure, value-semantic store of conversation state: the feed (sorted by last
/// activity) and the messages of open conversations. All reconciliation of
/// paged loads and live `ConversationStreamEvent`s happens here so it is
/// unit-testable in isolation, without a controller, network, or actor.
public struct ConversationStore: Sendable {

    public private(set) var conversations: [Conversation] = []
    private var messagesByConversation: [ConversationID: [ConversationMessage]] = [:]

    public init() {}

    public func messages(for conversationID: ConversationID) -> [ConversationMessage] {
        messagesByConversation[conversationID] ?? []
    }

    /// Replace the feed from a paged load, sorted most-recent-activity first.
    public mutating func setFeed(_ conversations: [Conversation]) {
        self.conversations = conversations.sorted { $0.lastActivity > $1.lastActivity }
    }

    /// Insert/replace messages keyed by their gapless id, keeping oldest first.
    /// Dedupes the send-response echo against the same message arriving on the
    /// stream (both carry the server-assigned id).
    public mutating func mergeMessages(_ incoming: [ConversationMessage], into conversationID: ConversationID) {
        guard !incoming.isEmpty else { return }
        let current = messagesByConversation[conversationID] ?? []

        var byID = Dictionary(
            current.map { ($0.id, $0) },
            uniquingKeysWith: { _, new in new }
        )
        for message in incoming {
            byID[message.id] = message
        }
        messagesByConversation[conversationID] = byID.values.sorted { $0.id < $1.id }
    }

    /// The signed-in user's READ watermark for a conversation, as last reported by
    /// the feed/stream and locally advanced after each successful markRead.
    public func selfReadPointer(for conversationID: ConversationID, selfUserID: UserID) -> MessageID? {
        conversations.first { $0.id == conversationID }?.selfReadPointer(for: selfUserID)
    }

    /// Locally advance the signed-in user's READ watermark after a successful
    /// markRead so the next call can short-circuit.
    public mutating func advanceSelfReadPointer(to messageID: MessageID, in conversationID: ConversationID, selfUserID: UserID) {
        advanceReadPointer(to: messageID, for: selfUserID, in: conversationID)
    }

    /// Monotonically advance a member's READ watermark; never moves it backward.
    /// `date` is when the pointer was advanced (for the read receipt); stored
    /// only when the watermark actually moves.
    private mutating func advanceReadPointer(to messageID: MessageID, for userID: UserID, at date: Date? = nil, in conversationID: ConversationID) {
        guard let convoIndex = conversations.firstIndex(where: { $0.id == conversationID }),
              let memberIndex = conversations[convoIndex].members.firstIndex(where: { $0.userID == userID }) else {
            return
        }
        if let current = conversations[convoIndex].members[memberIndex].readPointer, messageID <= current {
            return
        }
        conversations[convoIndex].members[memberIndex].readPointer = messageID
        conversations[convoIndex].members[memberIndex].readPointerTimestamp = date
    }

    /// Bump a conversation's last message + activity and re-sort the feed.
    public mutating func setLastMessage(_ message: ConversationMessage, in conversationID: ConversationID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[index].lastMessage = message
        conversations[index].lastActivity = message.date
        sort()
    }

    /// Apply a live event from the per-user event stream.
    public mutating func apply(_ event: ConversationStreamEvent) {
        switch event {
        case .newMessages(let conversationID, let messages):
            mergeMessages(messages, into: conversationID)
            if let latest = messages.max(by: { $0.id < $1.id }) {
                setLastMessage(latest, in: conversationID)
            }
        case .metadataRefresh(let conversation):
            upsert(conversation)
        case .lastActivityChanged(let conversationID, let date):
            guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
            conversations[index].lastActivity = date
            sort()
        case .readPointersChanged(let conversationID, let pointers):
            for pointer in pointers {
                advanceReadPointer(to: pointer.value, for: pointer.userID, at: pointer.date, in: conversationID)
            }
        }
    }

    private mutating func upsert(_ conversation: Conversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        } else {
            conversations.append(conversation)
        }
        sort()
    }

    private mutating func sort() {
        conversations.sort { $0.lastActivity > $1.lastActivity }
    }
}
