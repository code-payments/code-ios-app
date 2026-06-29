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

    private func cashMessage(id: UInt64, senderID: UUID?, amount: Decimal, mint: PublicKey = .usdf) -> ConversationMessage {
        let fiat = ExchangedFiat(
            onChainAmount: TokenAmount(quarks: 0, mint: mint),
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

    /// The message rows from a preview result, ignoring any date separators.
    private func messageRows(_ items: [ChatItem]) -> [ChatMessage] {
        items.compactMap { if case .message(let message) = $0 { message } else { nil } }
    }

    /// The date-separator labels from a preview result, in order.
    private func separators(_ items: [ChatItem]) -> [String] {
        items.compactMap { if case .dateSeparator(_, let text) = $0 { text } else { nil } }
    }

    // MARK: - Sender resolution

    @Test("My messages map to .me sender")
    func mySenderMapsToMe() {
        let messages = [textMessage(id: 1, senderID: meID, text: "hello")]
        let items = ChatItem.preview(from: messages, selfUserID: meID)

        guard let msg = messageRows(items).first else {
            Issue.record("Expected a .message item")
            return
        }
        #expect(msg.sender == .me)
    }

    @Test("Other party messages map to .other sender")
    func otherSenderMapsToOther() {
        let messages = [textMessage(id: 1, senderID: otherID, text: "hi")]
        let items = ChatItem.preview(from: messages, selfUserID: meID)

        guard let msg = messageRows(items).first else {
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

        guard let msg = messageRows(items).first else {
            Issue.record("Expected a .message item")
            return
        }
        #expect(msg.content == .text("see you soon"))
    }

    @Test("Cash message maps to .cash content with formatted amount and flag; unbranded by default")
    func cashContentMaps() {
        let messages = [cashMessage(id: 1, senderID: otherID, amount: 5.00)]
        let items = ChatItem.preview(from: messages, selfUserID: meID)

        guard let msg = messageRows(items).first else {
            Issue.record("Expected a .message item")
            return
        }
        guard case .cash(let cash) = msg.content else {
            Issue.record("Expected .cash content")
            return
        }
        // Without resolved branding the token label and icon are empty — no misleading fallback.
        #expect(cash.token == "")
        #expect(cash.iconURL == nil)
        #expect(cash.flagImageName != nil)
        // Amount is a non-empty formatted string (locale-sensitive; just check non-empty)
        #expect(!cash.amount.isEmpty)
    }

    @Test("Cash row uses the resolved mint name and icon when provided")
    func cashUsesResolvedBranding() {
        let icon = URL(string: "https://example.com/jeffy.png")!
        let messages = [cashMessage(id: 1, senderID: otherID, amount: 0.1, mint: .usdc)]
        let items = ChatItem.preview(from: messages, selfUserID: meID, mintBranding: [.usdc: MintBrandingInfo(name: "Jeffy", iconURL: icon)])

        guard let msg = messageRows(items).first, case .cash(let cash) = msg.content else {
            Issue.record("Expected .cash content")
            return
        }
        #expect(cash.token == "Jeffy")
        #expect(cash.iconURL == icon)
    }

    @Test("Cash row shows no token label or icon when the mint isn't resolved")
    func cashUnresolvedMintShowsNoBranding() {
        let messages = [cashMessage(id: 1, senderID: otherID, amount: 0.1, mint: .usdc)]
        // Branding keyed by a different mint must not apply.
        let items = ChatItem.preview(from: messages, selfUserID: meID, mintBranding: [.usdf: MintBrandingInfo(name: "Jeffy", iconURL: nil)])

        guard let msg = messageRows(items).first, case .cash(let cash) = msg.content else {
            Issue.record("Expected .cash content")
            return
        }
        #expect(cash.token == "")
        #expect(cash.iconURL == nil)
    }

    @Test("Message id is the string form of MessageID.value")
    func messageIDMapsToString() {
        let messages = [textMessage(id: 42, senderID: meID, text: "test")]
        let items = ChatItem.preview(from: messages, selfUserID: meID)

        guard let msg = messageRows(items).first else {
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
        #expect(messageRows(items).count == 2)
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

    // MARK: - Date separators

    @Test("A date separator opens the transcript")
    func separatorOpensTranscript() {
        let messages = [textMessage(id: 1, senderID: meID, text: "hi")]
        let items = ChatItem.preview(from: messages, selfUserID: meID)

        guard case .dateSeparator = items.first else {
            Issue.record("Expected the first item to be a date separator")
            return
        }
        #expect(separators(items).count == 1)
    }

    @Test("Messages within the gap share a single opening separator")
    func messagesWithinGapShareSeparator() {
        // ids 1 and 2 → dates 1s apart, well under the 15-minute gap.
        let messages = [
            textMessage(id: 1, senderID: meID, text: "a"),
            textMessage(id: 2, senderID: meID, text: "b"),
        ]
        let items = ChatItem.preview(from: messages, selfUserID: meID)
        #expect(separators(items).count == 1)
    }

    @Test("A gap longer than 15 minutes inserts another separator")
    func gapInsertsSeparator() {
        // ids 1 and 1000 → dates 999s (~16.6 min) apart, beyond the 15-minute gap.
        let messages = [
            textMessage(id: 1, senderID: meID, text: "a"),
            textMessage(id: 1000, senderID: meID, text: "b"),
        ]
        let items = ChatItem.preview(from: messages, selfUserID: meID)
        #expect(separators(items).count == 2)
    }
}
