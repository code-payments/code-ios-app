//
//  ChatMessageMappingTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashCore
import FlipcashUI
@testable import Flipcash

@MainActor
@Suite("ChatItem mapping from conversation")
struct ChatMessageMappingTests {

    private let me = UUID()
    private let them = UUID()
    private let base = Date(timeIntervalSince1970: 1_000_000)

    private func text(_ id: UInt64, _ sender: UUID, _ body: String, after offset: TimeInterval) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id),
            senderID: sender,
            content: .text(body),
            date: base.addingTimeInterval(offset),
            unreadSeq: id
        )
    }

    /// The message rows, dropping the interleaved date separators.
    private func messageRows(_ items: [ChatItem]) -> [ChatMessage] {
        items.compactMap { if case .message(let message) = $0 { message } else { nil } }
    }

    private func separatorCount(_ items: [ChatItem]) -> Int {
        items.filter { if case .dateSeparator = $0 { true } else { false } }.count
    }

    private func receiptText(_ items: [ChatItem]) -> String? {
        items.compactMap { if case .message(let message) = $0 { message.receipt } else { nil } }.last
    }

    private func sending(_ clientID: UUID, _ body: String, after offset: TimeInterval) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: .max), senderID: me, content: .text(body),
            date: base.addingTimeInterval(offset), unreadSeq: 0,
            status: .sending, clientMessageID: clientID
        )
    }

    private func deliveryStates(_ items: [ChatItem]) -> [ChatMessage.DeliveryState] {
        messageRows(items).map(\.deliveryState)
    }

    @Test("Same-sender run within the gap groups; a sender change breaks it; gaps add separators")
    func grouping() {
        let messages = [
            text(1, me, "a", after: 0),
            text(2, me, "b", after: 60),            // +1m, same sender → grouped with #1
            text(3, them, "c", after: 120),         // other sender → breaks the run
            text(4, me, "d", after: 120 + 16 * 60), // me again, but a gap from #3 → standalone
        ]

        let items = ChatItem.from(messages, selfUserID: me)
        let rows = messageRows(items)

        #expect(rows.map(\.sender) == [.me, .me, .other, .me])
        #expect(rows[0].content == .text("a"))
        #expect(rows[0].isContinuedByNext)           // #1 → #2 same-sender run
        #expect(rows[1].isContinuationFromPrevious)
        #expect(!rows[1].isContinuedByNext)          // #2 → #3 sender change
        #expect(!rows[2].isContinuationFromPrevious)
        #expect(!rows[2].isContinuedByNext)
        #expect(!rows[3].isContinuationFromPrevious) // gap from #3
        // One separator opens the transcript; another breaks the 16-minute gap before #4.
        #expect(separatorCount(items) == 2)
    }

    @Test("A gap longer than 15 minutes breaks a same-sender run")
    func gapBreaksRun() {
        let messages = [
            text(1, me, "a", after: 0),
            text(2, me, "b", after: 16 * 60), // +16m, same sender, but past the gap
        ]

        let rows = messageRows(ChatItem.from(messages, selfUserID: me))

        #expect(!rows[0].isContinuedByNext)
        #expect(!rows[1].isContinuationFromPrevious)
    }

    @Test("Cash messages map to formatted cash content with a currency flag")
    func cash() {
        let fiat = ExchangedFiat(
            nativeAmount: FiatAmount(value: 5, currency: .usd),
            rate: Rate(fx: 1, currency: .usd)
        )
        let messages = [
            ConversationMessage(id: MessageID(value: 1), senderID: them, content: .cash(fiat), date: base, unreadSeq: 1),
        ]

        let rows = messageRows(ChatItem.from(messages, selfUserID: me))

        #expect(rows.count == 1)
        #expect(rows[0].sender == .other) // sent by `them`, not me → received
        guard case .cash(let cash) = rows[0].content else {
            Issue.record("expected cash content, got \(rows[0].content)")
            return
        }
        #expect(cash.token == "Cash")
        #expect(cash.amount == fiat.nativeAmount.formatted())
        #expect(cash.flagImageName != nil) // currency flag derived from the currency
    }

    @Test("The latest sent message reads Delivered until the read pointer reaches it")
    func receiptDelivered() {
        let items = ChatItem.from(
            [text(1, me, "hi", after: 0)],
            selfUserID: me,
            counterpartRead: (pointer: MessageID(value: 0), date: nil)
        )
        #expect(receiptText(items) == "Delivered")
    }

    @Test("A read pointer without a timestamp reads Read")
    func receiptReadWithoutDate() {
        let items = ChatItem.from(
            [text(1, me, "hi", after: 0)],
            selfUserID: me,
            counterpartRead: (pointer: MessageID(value: 1), date: nil)
        )
        #expect(receiptText(items) == "Read")
    }

    @Test("Appending one sent message is a single clean insert — the receipt rides on the message")
    func appendingOneMessageIsACleanInsert() {
        // Two of my messages, then I append a third (same sender, within the grouping gap).
        let before = ChatItem.from([text(1, me, "a", after: 0), text(2, me, "b", after: 60)], selfUserID: me)
        let after = ChatItem.from([text(1, me, "a", after: 0), text(2, me, "b", after: 60), text(3, me, "c", after: 120)], selfUserID: me)

        let beforeByID = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0) })
        let afterByID = Dictionary(uniqueKeysWithValues: after.map { ($0.id, $0) })
        let beforeIDs = Set(beforeByID.keys)
        let afterIDs = Set(afterByID.keys)

        let inserted = afterIDs.subtracting(beforeIDs)
        let deleted = beforeIDs.subtracting(afterIDs)
        let reconfigured = beforeIDs.intersection(afterIDs).filter { beforeByID[$0] != afterByID[$0] }
        func receipt(_ id: String) -> String? {
            if case .message(let m) = afterByID[id] { m.receipt } else { nil }
        }

        // The delivery line rides on the message, so there is no separate receipt row to insert or
        // delete — appending is purely the new bubble. ChatLayout receives one clean insert.
        #expect(inserted == ["3"])
        #expect(deleted.isEmpty)
        // The previous bubble reconfigures in place — it both loses the receipt and flips its grouping
        // flag — via reconfigureItems, which does not animate as an insert/delete.
        #expect(reconfigured == ["2"])
        // Concretely: the receipt moved from the old latest bubble onto the new one.
        #expect(receipt("3") == "Delivered")
        #expect(receipt("2") == nil)
    }

    @Test("A read from days ago renders the relative day, not a bare time")
    func receiptUsesRelativeDay() {
        // Guards the hookup: with the old `formattedTime()` this read as "Read 3:42 PM".
        let calendar = Calendar.current
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: noon)!
        let weekday = calendar.weekdaySymbols[calendar.component(.weekday, from: threeDaysAgo) - 1]

        let items = ChatItem.from(
            [text(1, me, "hi", after: 0)],
            selfUserID: me,
            counterpartRead: (pointer: MessageID(value: 1), date: threeDaysAgo)
        )
        #expect(receiptText(items) == "Read \(weekday)")
    }

    @Test("A sending row shows no status line and keeps the prior delivered receipt")
    func sendingMapsToState() {
        let clientID = UUID()
        let items = ChatItem.from(
            [text(1, me, "a", after: 0), sending(clientID, "b", after: 60)],
            selfUserID: me,
            counterpartRead: (pointer: MessageID(value: 0), date: nil)
        )
        #expect(deliveryStates(items) == [.normal, .sending])
        // "b" (sending) shows nothing; the prior delivered "a" keeps its "Delivered" line.
        let rows = messageRows(items)
        #expect(rows.first?.receipt == "Delivered")
        #expect(rows.last?.id == clientID.uuidString)
        #expect(rows.last?.receipt == nil)
    }

    @Test("A failed row shows its own line without stripping the prior delivered receipt")
    func failedMapsToState() {
        let clientID = UUID()
        var msg = sending(clientID, "b", after: 60)
        msg.status = .failed
        let items = ChatItem.from(
            [text(1, me, "a", after: 0), msg],
            selfUserID: me,
            counterpartRead: (pointer: MessageID(value: 0), date: nil)
        )
        #expect(deliveryStates(items) == [.normal, .failed])
        let rows = messageRows(items)
        #expect(rows.first?.receipt == "Delivered")                     // prior delivered receipt preserved
        #expect(rows.last?.receipt == "Not Delivered. Tap to retry")    // failed row shows its own line
    }

    @Test("A settling send's Delivered receipt is held back, then shows once the gate clears")
    func suppressedReceiptWhileSettling() {
        let read = (pointer: MessageID(value: 0), date: Date?.none)
        // While the row is still settling (its id is suppressed), no receipt shows.
        let settling = ChatItem.from([text(1, me, "hi", after: 0)], selfUserID: me, counterpartRead: read, suppressReceiptFor: "1")
        #expect(receiptText(settling) == nil)
        // Once the gate clears, "Delivered" appears.
        let settled = ChatItem.from([text(1, me, "hi", after: 0)], selfUserID: me, counterpartRead: read)
        #expect(receiptText(settled) == "Delivered")
    }
}
