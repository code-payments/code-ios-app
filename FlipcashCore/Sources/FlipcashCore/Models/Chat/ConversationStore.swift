//
//  ConversationStore.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Pure, value-semantic store of conversation state: the feed (sorted by last
/// activity) and the messages of open conversations. All reconciliation of
/// paged loads and live `ChatStreamEvent`s happens here so it is unit-testable
/// in isolation, without a controller, network, or actor.
public struct ConversationStore: Sendable {

    public private(set) var conversations: [Conversation] = []
    private var messagesByChat: [ChatID: [ChatMessage]] = [:]

    public init() {}

    public func messages(for chatID: ChatID) -> [ChatMessage] {
        messagesByChat[chatID] ?? []
    }

    /// Replace the feed from a paged load, sorted most-recent-activity first.
    public mutating func setFeed(_ conversations: [Conversation]) {
        self.conversations = conversations.sorted { $0.lastActivity > $1.lastActivity }
    }

    /// Insert/replace messages keyed by their gapless id, keeping oldest first.
    /// Dedupes the send-response echo against the same message arriving on the
    /// stream (both carry the server-assigned id).
    public mutating func mergeMessages(_ incoming: [ChatMessage], into chatID: ChatID) {
        guard !incoming.isEmpty else { return }
        let current = messagesByChat[chatID] ?? []
        let sortedIncoming = incoming.sorted { $0.id < $1.id }

        // Fast path: the live case is appending strictly-newer messages to an
        // existing transcript. Equal ids (the send echo) route to the fallback
        // so last-write-wins dedup still holds.
        if let lastCurrent = current.last, let firstIncoming = sortedIncoming.first,
           firstIncoming.id > lastCurrent.id {
            var merged = current
            merged.reserveCapacity(current.count + sortedIncoming.count)
            merged.append(contentsOf: sortedIncoming)
            messagesByChat[chatID] = merged
            return
        }

        // Fallback: first load, out-of-order backfill, or a duplicate id.
        var byID = Dictionary(
            current.map { ($0.id, $0) },
            uniquingKeysWith: { _, new in new }
        )
        for message in sortedIncoming {
            byID[message.id] = message
        }
        messagesByChat[chatID] = byID.values.sorted { $0.id < $1.id }
    }

    /// The signed-in user's READ watermark for a chat, as last reported by the
    /// feed/stream and locally advanced after each successful markRead.
    public func selfReadPointer(for chatID: ChatID, selfUserID: UserID) -> MessageID? {
        conversations.first { $0.id == chatID }?.selfReadPointer(for: selfUserID)
    }

    /// Locally advance the signed-in user's READ watermark after a successful
    /// markRead so the next call can short-circuit.
    public mutating func advanceSelfReadPointer(to messageID: MessageID, in chatID: ChatID, selfUserID: UserID) {
        advanceReadPointer(to: messageID, for: selfUserID, in: chatID)
    }

    /// Monotonically advance a member's READ watermark; never moves it backward.
    private mutating func advanceReadPointer(to messageID: MessageID, for userID: UserID, in chatID: ChatID) {
        guard let convoIndex = conversations.firstIndex(where: { $0.id == chatID }),
              let memberIndex = conversations[convoIndex].members.firstIndex(where: { $0.userID == userID }) else {
            return
        }
        if let current = conversations[convoIndex].members[memberIndex].readPointer, messageID <= current {
            return
        }
        conversations[convoIndex].members[memberIndex].readPointer = messageID
    }

    /// Bump a conversation's last message + activity and re-sort the feed.
    public mutating func setLastMessage(_ message: ChatMessage, in chatID: ChatID) {
        guard let index = conversations.firstIndex(where: { $0.id == chatID }) else { return }
        conversations[index].lastMessage = message
        conversations[index].lastActivity = message.date
        sort()
    }

    /// Apply a live event from the per-user event stream.
    public mutating func apply(_ event: ChatStreamEvent) {
        switch event {
        case .newMessages(let chatID, let messages):
            mergeMessages(messages, into: chatID)
            if let latest = messages.max(by: { $0.id < $1.id }) {
                setLastMessage(latest, in: chatID)
            }
        case .metadataRefresh(let conversation):
            upsert(conversation)
        case .lastActivityChanged(let chatID, let date):
            guard let index = conversations.firstIndex(where: { $0.id == chatID }) else { return }
            conversations[index].lastActivity = date
            sort()
        case .readPointersChanged(let chatID, let pointers):
            for pointer in pointers {
                advanceReadPointer(to: pointer.value, for: pointer.userID, in: chatID)
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
