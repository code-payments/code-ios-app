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
@Suite("ChatMessage mapping from conversation")
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

    @Test("Same-sender run within the gap groups; a sender change breaks it")
    func grouping() {
        let messages = [
            text(1, me, "a", after: 0),
            text(2, me, "b", after: 60),            // +1m, same sender → grouped with #1
            text(3, them, "c", after: 120),         // other sender → breaks the run
            text(4, me, "d", after: 120 + 16 * 60), // me again, but a gap from #3 → standalone
        ]

        let rows = ChatMessage.from(messages, selfUserID: me)

        #expect(rows.map(\.sender) == [.me, .me, .other, .me])
        #expect(rows[0].content == .text("a"))
        #expect(rows[0].isContinuedByNext)           // #1 → #2 same-sender run
        #expect(rows[1].isContinuationFromPrevious)
        #expect(!rows[1].isContinuedByNext)          // #2 → #3 sender change
        #expect(!rows[2].isContinuationFromPrevious)
        #expect(!rows[2].isContinuedByNext)
        #expect(!rows[3].isContinuationFromPrevious) // gap from #3
    }

    @Test("A gap longer than 15 minutes breaks a same-sender run")
    func gapBreaksRun() {
        let messages = [
            text(1, me, "a", after: 0),
            text(2, me, "b", after: 16 * 60), // +16m, same sender, but past the gap
        ]

        let rows = ChatMessage.from(messages, selfUserID: me)

        #expect(!rows[0].isContinuedByNext)
        #expect(!rows[1].isContinuationFromPrevious)
    }

    @Test("Cash messages map to formatted cash content")
    func cash() {
        let fiat = ExchangedFiat(
            nativeAmount: FiatAmount(value: 5, currency: .usd),
            rate: Rate(fx: 1, currency: .usd)
        )
        let messages = [
            ConversationMessage(id: MessageID(value: 1), senderID: them, content: .cash(fiat), date: base, unreadSeq: 1),
        ]

        let rows = ChatMessage.from(messages, selfUserID: me)

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
}
