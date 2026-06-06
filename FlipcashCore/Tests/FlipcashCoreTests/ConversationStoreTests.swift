//
//  ConversationStoreTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import FlipcashCore

@Suite("ConversationStore reconciliation")
struct ConversationStoreTests {

    private func conversationID(_ byte: UInt8) -> ConversationID {
        ConversationID(data: Data(repeating: byte, count: 32))
    }

    private func conversation(_ byte: UInt8, lastActivity: TimeInterval) -> Conversation {
        Conversation(
            id: conversationID(byte),
            members: [],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: lastActivity)
        )
    }

    private func message(_ id: UInt64, _ text: String = "hi", at: TimeInterval = 0) -> ConversationMessage {
        ConversationMessage(id: MessageID(value: id), senderID: nil, text: text, date: Date(timeIntervalSince1970: at), unreadSeq: 0)
    }

    @Test("setFeed sorts by last activity, most recent first")
    func feedSortsByActivity() {
        var store = ConversationStore()
        store.setFeed([
            conversation(1, lastActivity: 100),
            conversation(2, lastActivity: 300),
            conversation(3, lastActivity: 200),
        ])
        #expect(store.conversations.map(\.id) == [conversationID(2), conversationID(3), conversationID(1)])
    }

    @Test("mergeMessages dedupes by id and keeps oldest first")
    func messagesMergeGapless() {
        var store = ConversationStore()
        store.mergeMessages([message(3), message(1)], into: conversationID(1))
        store.mergeMessages([message(1, "updated"), message(2)], into: conversationID(1))

        let messages = store.messages(for: conversationID(1))
        #expect(messages.map(\.id.value) == [1, 2, 3])
        #expect(messages.first?.text == "updated") // last write wins per id
    }

    @Test("mergeMessages fast-appends strictly-newer messages in order")
    func messagesFastAppend() {
        var store = ConversationStore()
        store.mergeMessages([message(1), message(2)], into: conversationID(1))
        store.mergeMessages([message(3)], into: conversationID(1))            // strictly newer → fast path
        store.mergeMessages([message(5), message(4)], into: conversationID(1)) // newer batch, out of order within
        #expect(store.messages(for: conversationID(1)).map(\.id.value) == [1, 2, 3, 4, 5])
    }

    @Test("mergeMessages dedupes a re-delivered newest message (send echo)")
    func messagesDedupeEcho() {
        var store = ConversationStore()
        store.mergeMessages([message(1), message(2)], into: conversationID(1))
        store.mergeMessages([message(2, "echo")], into: conversationID(1))    // equal id → fallback dedups
        let messages = store.messages(for: conversationID(1))
        #expect(messages.map(\.id.value) == [1, 2])
        #expect(messages.last?.text == "echo")
    }

    @Test("newMessages event appends and bumps the conversation's last activity")
    func applyNewMessages() {
        var store = ConversationStore()
        store.setFeed([conversation(1, lastActivity: 100), conversation(2, lastActivity: 200)])
        store.apply(.newMessages(conversationID: conversationID(1), messages: [message(5, "yo", at: 500)]))

        #expect(store.messages(for: conversationID(1)).map(\.id.value) == [5])
        // conversation 1 moves to the front after its new activity
        #expect(store.conversations.first?.id == conversationID(1))
        #expect(store.conversations.first?.lastMessage?.text == "yo")
    }

    @Test("lastActivityChanged re-sorts the feed")
    func applyLastActivityChanged() {
        var store = ConversationStore()
        store.setFeed([conversation(1, lastActivity: 100), conversation(2, lastActivity: 200)])
        store.apply(.lastActivityChanged(conversationID: conversationID(1), date: Date(timeIntervalSince1970: 999)))
        #expect(store.conversations.first?.id == conversationID(1))
    }

    @Test("metadataRefresh upserts a new conversation")
    func applyMetadataRefreshInserts() {
        var store = ConversationStore()
        store.setFeed([conversation(1, lastActivity: 100)])
        store.apply(.metadataRefresh(conversation(2, lastActivity: 999)))
        #expect(store.conversations.count == 2)
        #expect(store.conversations.first?.id == conversationID(2))
    }

    @Test("readPointersChanged advances a member's READ watermark monotonically")
    func applyReadPointers() {
        let me = UUID()
        var store = ConversationStore()
        store.setFeed([Conversation(
            id: conversationID(1),
            members: [ConversationMember(userID: me, displayName: "", readPointer: MessageID(value: 2))],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0)
        )])

        store.apply(.readPointersChanged(conversationID: conversationID(1), pointers: [MemberReadPointer(userID: me, value: MessageID(value: 5))]))
        #expect(store.selfReadPointer(for: conversationID(1), selfUserID: me) == MessageID(value: 5))

        // A stale watermark never moves it backward.
        store.apply(.readPointersChanged(conversationID: conversationID(1), pointers: [MemberReadPointer(userID: me, value: MessageID(value: 3))]))
        #expect(store.selfReadPointer(for: conversationID(1), selfUserID: me) == MessageID(value: 5))
    }
}
