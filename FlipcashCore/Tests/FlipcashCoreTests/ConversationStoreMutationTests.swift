//
//  ConversationStoreMutationTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import FlipcashCore

@Suite("ConversationStore mutation overlay")
struct ConversationStoreMutationTests {

    private let sender = UUID()

    private func conversationID(_ byte: UInt8) -> ConversationID {
        ConversationID(data: Data(repeating: byte, count: 32))
    }

    private func message(_ id: UInt64, _ text: String, eventSequence: UInt64) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id), senderID: sender, content: .text(text),
            date: Date(timeIntervalSince1970: TimeInterval(id)), unreadSeq: id, eventSequence: eventSequence
        )
    }

    private func texts(_ messages: [ConversationMessage]) -> [String] {
        messages.map {
            switch $0.content {
            case .text(let value): value
            case .deleted:         "<deleted>"
            case .cash:            "<cash>"
            }
        }
    }

    @Test("An edit overlay replaces the stored text")
    func editOverlayReplacesText() {
        var store = ConversationStore()
        let id = conversationID(1)
        store.applyMutation(
            MutationEntry(messageID: MessageID(value: 2), kind: .edited("after"), expectedSequence: 5),
            in: id
        )

        let displayed = store.displayedMessages(
            for: id,
            over: [message(1, "one", eventSequence: 4), message(2, "before", eventSequence: 5)]
        )
        #expect(texts(displayed) == ["one", "after"])
    }

    @Test("An edit overlay marks the message as edited so the marker shows immediately")
    func editOverlayMarksEdited() {
        var store = ConversationStore()
        let id = conversationID(1)
        store.applyMutation(
            MutationEntry(messageID: MessageID(value: 2), kind: .edited("after"), expectedSequence: 5),
            in: id
        )

        let displayed = store.displayedMessages(for: id, over: [message(2, "before", eventSequence: 5)])
        #expect(displayed.first?.lastEditedTs != nil)
    }

    @Test("A delete overlay turns the message into a tombstone attributed to its sender")
    func deleteOverlayTombstones() {
        var store = ConversationStore()
        let id = conversationID(1)
        store.applyMutation(
            MutationEntry(messageID: MessageID(value: 2), kind: .deleted, expectedSequence: 5),
            in: id
        )

        let displayed = store.displayedMessages(for: id, over: [message(2, "before", eventSequence: 5)])
        guard case .deleted(let deletion) = displayed.first?.content else {
            Issue.record("expected a tombstone")
            return
        }
        #expect(deletion.deletedBy == sender)
    }

    @Test("A stored row that out-versions the overlay wins — the server's answer landed")
    func newerStoredRowBeatsTheOverlay() {
        var store = ConversationStore()
        let id = conversationID(1)
        store.applyMutation(
            MutationEntry(messageID: MessageID(value: 2), kind: .edited("mine"), expectedSequence: 5),
            in: id
        )

        let displayed = store.displayedMessages(for: id, over: [message(2, "theirs", eventSequence: 6)])
        #expect(texts(displayed) == ["theirs"])
    }

    @Test("Dropping the overlay restores the stored text")
    func droppingOverlayRestoresStoredText() {
        var store = ConversationStore()
        let id = conversationID(1)
        store.applyMutation(
            MutationEntry(messageID: MessageID(value: 2), kind: .edited("after"), expectedSequence: 5),
            in: id
        )
        store.dropMutation(for: MessageID(value: 2), in: id)

        let displayed = store.displayedMessages(for: id, over: [message(2, "before", eventSequence: 5)])
        #expect(texts(displayed) == ["before"])
    }

    @Test("An overlay in one conversation does not leak into another")
    func overlayIsScopedToItsConversation() {
        var store = ConversationStore()
        store.applyMutation(
            MutationEntry(messageID: MessageID(value: 2), kind: .edited("after"), expectedSequence: 5),
            in: conversationID(1)
        )

        let displayed = store.displayedMessages(for: conversationID(2), over: [message(2, "before", eventSequence: 5)])
        #expect(texts(displayed) == ["before"])
    }
}
