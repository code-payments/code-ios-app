//
//  ChatQuoteMappingTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashCore
import FlipcashUI
@testable import Flipcash

@Suite("Reply quote mapping")
struct ChatQuoteMappingTests {

    private let me = UUID()
    private let them = UUID()
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func message(
        id: UInt64,
        from sender: UUID?,
        content: ConversationMessage.Content,
        repliedTo: UInt64? = nil,
        offset: TimeInterval = 0
    ) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id),
            senderID: sender,
            content: content,
            date: start.addingTimeInterval(offset),
            unreadSeq: id,
            eventSequence: id,
            repliedTo: repliedTo.map { MessageID(value: $0) }
        )
    }

    private func quotes(
        _ messages: [ConversationMessage],
        resolving pool: [ConversationMessage] = []
    ) -> [ChatQuote?] {
        let byID = Dictionary(uniqueKeysWithValues: (messages + pool).map { ($0.id, $0) })
        return ChatItem.from(
            messages,
            selfUserID: me,
            counterpartName: "Ada",
            quotedMessage: { byID[$0] }
        ).compactMap { item in
            if case .message(let message) = item { return message.quote } else { return nil }
        }
    }

    @Test("A reply to a message in the window quotes its author and text")
    func replyToWindowedMessage_resolves() throws {
        let original = message(id: 1, from: them, content: .text("dinner at 7?"))
        let reply = message(id: 2, from: me, content: .text("works"), repliedTo: 1, offset: 5)
        let quote = try #require(quotes([original, reply]).last ?? nil)
        #expect(quote.authorName == "Ada")
        #expect(quote.snippet == "dinner at 7?")
        #expect(quote.kind == .text)
        #expect(quote.stableID == original.stableID)
    }

    @Test("A reply to my own message names me")
    func replyToOwnMessage_namesMe() throws {
        let original = message(id: 1, from: me, content: .text("dinner at 7?"))
        let reply = message(id: 2, from: them, content: .text("works"), repliedTo: 1, offset: 5)
        let quote = try #require(quotes([original, reply]).last ?? nil)
        #expect(quote.authorName == "You")
    }

    @Test("A reply to a message outside the local database renders as unavailable and cannot be jumped to")
    func replyToUnknownMessage_isUnavailable() throws {
        let reply = message(id: 2, from: me, content: .text("works"), repliedTo: 99, offset: 5)
        let quote = try #require(quotes([reply]).last ?? nil)
        #expect(quote.kind == .unavailable)
        #expect(quote.snippet == ChatQuote.unavailableSnippet)
        #expect(quote.isJumpable == false)
    }

    @Test("A reply to a deleted message says so and cannot be jumped to")
    func replyToDeletedMessage_isUnavailable() throws {
        let original = message(
            id: 1, from: them,
            content: .deleted(ConversationMessage.Deletion(deletedBy: them, deletedAt: start))
        )
        let reply = message(id: 2, from: me, content: .text("works"), repliedTo: 1, offset: 5)
        // The tombstone itself is filtered out of the transcript under `.hidden`, so it is supplied
        // through the resolution pool rather than the window.
        let quote = try #require(quotes([reply], resolving: [original]).last ?? nil)
        #expect(quote.kind == .unavailable)
        #expect(quote.snippet == ChatQuote.deletedSnippet)
        #expect(quote.isJumpable == false)
    }

    private func fiat(_ amount: Decimal) -> ExchangedFiat {
        ExchangedFiat(
            onChainAmount: TokenAmount(quarks: 0, mint: .usdf),
            nativeAmount: FiatAmount(value: amount, currency: .usd),
            currencyRate: Rate(fx: 1, currency: .usd)
        )
    }

    @Test("A reply to a payment quotes the formatted amount")
    func replyToCashMessage_quotesAmount() throws {
        let fiat = fiat(5)
        let original = message(id: 1, from: them, content: .cash(fiat))
        let reply = message(id: 2, from: me, content: .text("thanks!"), repliedTo: 1, offset: 5)
        let quote = try #require(quotes([original, reply]).last ?? nil)
        #expect(quote.kind == .cash)
        #expect(quote.snippet == fiat.nativeAmount.formatted())
    }

    @Test("A message that is not a reply carries no quote")
    func plainMessage_hasNoQuote() {
        let plain = message(id: 1, from: me, content: .text("hi"))
        #expect(quotes([plain]).last ?? nil == nil)
    }
}
