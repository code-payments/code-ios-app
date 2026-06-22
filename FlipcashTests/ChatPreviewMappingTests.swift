//
//  ChatPreviewMappingTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
import FlipcashUI

@Suite("ChatItem preview mapping") @MainActor
struct ChatPreviewMappingTests {

    // MARK: - Helpers

    private let meID = UUID()
    private let otherID = UUID()

    private func textMessage(id: UInt64, senderID: UUID?, text: String) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id),
            senderID: senderID,
            content: .text(text),
            date: Date(timeIntervalSince1970: Double(id)),
            unreadSeq: 0
        )
    }

    private func cashMessage(id: UInt64, senderID: UUID?, amount: Decimal) -> ConversationMessage {
        let fiat = ExchangedFiat(
            onChainAmount: TokenAmount(quarks: 0, mint: .usdf),
            nativeAmount: FiatAmount(value: amount, currency: .usd),
            currencyRate: Rate(fx: 1, currency: .usd)
        )
        return ConversationMessage(
            id: MessageID(value: id),
            senderID: senderID,
            content: .cash(fiat),
            date: Date(timeIntervalSince1970: Double(id)),
            unreadSeq: 0
        )
    }

    // MARK: - Sender resolution

    @Test("My messages map to .me sender")
    func mySenderMapsToMe() {
        let messages = [textMessage(id: 1, senderID: meID, text: "hello")]
        let items = ChatItem.preview(from: messages, selfUserID: meID)

        guard case .message(let msg) = items.first else {
            Issue.record("Expected a .message item")
            return
        }
        #expect(msg.sender == .me)
    }

    @Test("Other party messages map to .other sender")
    func otherSenderMapsToOther() {
        let messages = [textMessage(id: 1, senderID: otherID, text: "hi")]
        let items = ChatItem.preview(from: messages, selfUserID: meID)

        guard case .message(let msg) = items.first else {
            Issue.record("Expected a .message item")
            return
        }
        #expect(msg.sender == .other)
    }

    // MARK: - Content mapping

    @Test("Text message maps to .text content")
    func textContentMaps() {
        let messages = [textMessage(id: 1, senderID: meID, text: "see you soon")]
        let items = ChatItem.preview(from: messages, selfUserID: meID)

        guard case .message(let msg) = items.first else {
            Issue.record("Expected a .message item")
            return
        }
        #expect(msg.content == .text("see you soon"))
    }

    @Test("Cash message maps to .cash content with formatted amount and 'Cash' token")
    func cashContentMaps() {
        let messages = [cashMessage(id: 1, senderID: otherID, amount: 5.00)]
        let items = ChatItem.preview(from: messages, selfUserID: meID)

        guard case .message(let msg) = items.first else {
            Issue.record("Expected a .message item")
            return
        }
        guard case .cash(let cash) = msg.content else {
            Issue.record("Expected .cash content")
            return
        }
        #expect(cash.token == "Cash")
        // Amount is a non-empty formatted string (locale-sensitive; just check non-empty)
        #expect(!cash.amount.isEmpty)
    }

    @Test("Message id is the string form of MessageID.value")
    func messageIDMapsToString() {
        let messages = [textMessage(id: 42, senderID: meID, text: "test")]
        let items = ChatItem.preview(from: messages, selfUserID: meID)

        guard case .message(let msg) = items.first else {
            Issue.record("Expected a .message item")
            return
        }
        #expect(msg.id == "42")
    }

    // MARK: - Ordering (newest last, oldest first within slice)

    @Test("Items are returned in chronological order (oldest first)")
    func orderIsChronological() {
        let messages = [
            textMessage(id: 3, senderID: meID, text: "c"),
            textMessage(id: 1, senderID: meID, text: "a"),
            textMessage(id: 2, senderID: meID, text: "b"),
        ]
        let items = ChatItem.preview(from: messages, selfUserID: meID)
        let ids = items.compactMap { item -> String? in
            guard case .message(let m) = item else { return nil }
            return m.id
        }
        #expect(ids == ["1", "2", "3"])
    }

    // MARK: - Capping

    @Test("More than 3 messages: only the 3 most recent are returned")
    func capsAtDefaultLimit() {
        let messages = (1...5).map { i in
            textMessage(id: UInt64(i), senderID: meID, text: "msg \(i)")
        }
        let items = ChatItem.preview(from: messages, selfUserID: meID)
        let ids = items.compactMap { item -> String? in
            guard case .message(let m) = item else { return nil }
            return m.id
        }
        // Should be messages 3, 4, 5 (the most recent three), oldest first
        #expect(ids == ["3", "4", "5"])
    }

    @Test("Fewer than 3 messages: all are returned")
    func returnsAllWhenFewMessages() {
        let messages = [
            textMessage(id: 1, senderID: meID, text: "one"),
            textMessage(id: 2, senderID: otherID, text: "two"),
        ]
        let items = ChatItem.preview(from: messages, selfUserID: meID)
        #expect(items.count == 2)
    }

    @Test("Custom limit parameter is respected")
    func customLimitIsRespected() {
        let messages = (1...5).map { i in
            textMessage(id: UInt64(i), senderID: meID, text: "msg \(i)")
        }
        let items = ChatItem.preview(from: messages, selfUserID: meID, limit: 2)
        let ids = items.compactMap { item -> String? in
            guard case .message(let m) = item else { return nil }
            return m.id
        }
        #expect(ids == ["4", "5"])
    }

    @Test("Empty input returns empty array")
    func emptyInputReturnsEmpty() {
        let items = ChatItem.preview(from: [], selfUserID: meID)
        #expect(items.isEmpty)
    }
}
