//
//  MessageCapabilityTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import FlipcashCore

@Suite("Message capabilities")
struct MessageCapabilityTests {

    private let me = UUID()
    private let them = UUID()
    private let now = Date(timeIntervalSince1970: 2_000_000)

    private func text(_ body: String, from sender: UUID, eventSequence: UInt64 = 1, sentAgo: TimeInterval = 0) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: 1), senderID: sender, content: .text(body),
            date: now.addingTimeInterval(-sentAgo), unreadSeq: 1, eventSequence: eventSequence
        )
    }

    private func resolve(_ message: ConversationMessage, policy: MessagePolicy = .default) -> Set<MessageCapability> {
        MessageCapability.resolve(for: message, in: nil, as: me, policy: policy, now: now)
    }

    @Test("My own confirmed text can be copied, edited, and deleted")
    func ownTextIsFullyActionable() {
        #expect(resolve(text("hi", from: me)) == [.copy, .edit, .delete])
    }

    @Test("An unconfirmed message of mine offers nothing — it has no sequence to send as expected")
    func unconfirmedMessageOffersNothing() {
        #expect(resolve(text("hi", from: me, eventSequence: 0)).isEmpty)
    }

    @Test("Someone else's text can only be copied")
    func otherPersonsTextIsCopyOnly() {
        #expect(resolve(text("hi", from: them)) == [.copy])
    }

    @Test("A tombstone offers nothing")
    func tombstoneOffersNothing() {
        let tombstone = ConversationMessage(
            id: MessageID(value: 2), senderID: me,
            content: .deleted(.init(deletedBy: me, deletedAt: now)),
            date: now, unreadSeq: 1, eventSequence: 3
        )
        #expect(resolve(tombstone).isEmpty)
    }

    @Test("A cash message offers nothing in this scope — reply is the only capability it will ever have")
    func cashMessageOffersNothingYet() {
        let cash = ConversationMessage(
            id: MessageID(value: 3), senderID: me,
            content: .cash(ExchangedFiat(nativeAmount: .usd(20), rate: .oneToOne)),
            cashAction: .sent, date: now, unreadSeq: 1, eventSequence: 2
        )
        #expect(resolve(cash).isEmpty)
    }

    @Test("With an edit window configured, a message inside it stays editable")
    func messageInsideEditWindowIsEditable() {
        let policy = MessagePolicy(editWindow: 900, deletedPresentation: .placeholder)
        #expect(resolve(text("hi", from: me, sentAgo: 600), policy: policy) == [.copy, .edit, .delete])
    }

    @Test("With an edit window configured, a message past it can still be deleted but not edited")
    func messagePastEditWindowIsDeleteOnly() {
        let policy = MessagePolicy(editWindow: 900, deletedPresentation: .placeholder)
        #expect(resolve(text("hi", from: me, sentAgo: 1_200), policy: policy) == [.copy, .delete])
    }

    @Test("The default policy configures no edit window, so age never removes edit")
    func defaultPolicyHasNoEditWindow() {
        #expect(MessagePolicy.default.editWindow == nil)
        #expect(resolve(text("hi", from: me, sentAgo: 86_400)) == [.copy, .edit, .delete])
    }
}
