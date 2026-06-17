//
//  Database+ConversationsTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
@testable import FlipcashCore
@testable import Flipcash

@Suite("Conversation offline cache round-trip")
struct DatabaseConversationsTests {

    private let selfID = UUID()
    private let otherID = UUID()

    private func textMessage(id: UInt64, at seconds: TimeInterval = 0) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id),
            senderID: otherID,
            content: .text("message-\(id)"),
            date: Date(timeIntervalSince1970: seconds),
            unreadSeq: id
        )
    }

    /// The rate is synthesized from the amounts the same way the read path
    /// does, so round-trip equality covers the whole ExchangedFiat.
    private func cashMessage(id: UInt64) -> ConversationMessage {
        let onChain = TokenAmount(quarks: 12_500_000, mint: .usdf)
        let native = FiatAmount(value: Decimal(12.5), currency: .usd)
        return ConversationMessage(
            id: MessageID(value: id),
            senderID: selfID,
            content: .cash(ExchangedFiat(
                onChainAmount: onChain,
                nativeAmount: native,
                currencyRate: Rate(fx: native.value / onChain.decimalValue, currency: .usd)
            )),
            date: Date(timeIntervalSince1970: 50),
            unreadSeq: id
        )
    }

    private func conversation(
        byte: UInt8,
        members: [ConversationMember] = [],
        lastMessage: ConversationMessage? = nil,
        lastActivity: Date = Date(timeIntervalSince1970: 100)
    ) -> Conversation {
        Conversation(
            id: ConversationID.test(byte),
            members: members,
            lastMessage: lastMessage,
            lastActivity: lastActivity
        )
    }

    // MARK: - Messages -

    @Test("Text and cash messages round-trip, oldest first")
    func messagesRoundTrip() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let id = ConversationID.test(1)
        let messages = [textMessage(id: 2, at: 60), cashMessage(id: 3), textMessage(id: 1, at: 30)]

        try database.upsertConversationMessages(messages, conversationID: id)

        let loaded = try database.getConversationMessages(conversationID: id)
        #expect(loaded == [textMessage(id: 1, at: 30), textMessage(id: 2, at: 60), cashMessage(id: 3)])
    }

    @Test("Cash message native amounts round-trip exactly", arguments: ["0.1", "0.15", "0.33", "1.11", "2.23", "7.77", "99.99"])
    func cashMessagePrecisionRoundTrip(_ amountString: String) throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let id = ConversationID.test(1)

        let amount = Decimal(string: amountString)!
        let onChain = TokenAmount(quarks: 100_000_000, mint: .usdf)
        let native = FiatAmount(value: amount, currency: .usd)
        let message = ConversationMessage(
            id: MessageID(value: 1),
            senderID: selfID,
            content: .cash(ExchangedFiat(
                onChainAmount: onChain,
                nativeAmount: native,
                currencyRate: Rate(fx: native.value / onChain.decimalValue, currency: .usd)
            )),
            date: Date(timeIntervalSince1970: 50),
            unreadSeq: 1
        )

        try database.upsertConversationMessages([message], conversationID: id)
        let loaded = try database.getConversationMessages(conversationID: id)

        #expect(loaded.count == 1)
        let loadedMessage = try #require(loaded.first)
        switch loadedMessage.content {
        case .cash(let loadedExchanged):
            #expect(loadedExchanged.nativeAmount.value == amount)
        case .text:
            Issue.record("Expected cash message content")
        }
    }

    @Test("Cash messages with non-exact FX rates round-trip without precision loss", arguments: [
        (Decimal(string: "1")!, UInt64(3_000_000)),
        (Decimal(string: "100")!, UInt64(7_000_000)),
        (Decimal(string: "2.5")!, UInt64(7_000_000)),
        (Decimal(string: "1000")!, UInt64(17_000_000)),
        (Decimal(string: "0.001")!, UInt64(3_000_000)),
    ])
    func fxPrecisionRoundTrip(nativeValue: Decimal, quarks: UInt64) throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let id = ConversationID.test(1)

        let onChain = TokenAmount(quarks: quarks, mint: .usdf)
        let native = FiatAmount(value: nativeValue, currency: .usd)
        let message = ConversationMessage(
            id: MessageID(value: 1),
            senderID: selfID,
            content: .cash(ExchangedFiat(
                onChainAmount: onChain,
                nativeAmount: native,
                currencyRate: Rate(fx: native.value / onChain.decimalValue, currency: .usd)
            )),
            date: Date(timeIntervalSince1970: 50),
            unreadSeq: 1
        )

        try database.upsertConversationMessages([message], conversationID: id)
        let loaded = try database.getConversationMessages(conversationID: id)

        #expect(loaded == [message])
    }

    @Test("Re-upserting a message id replaces the row instead of duplicating it")
    func messageUpsertReplaces() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let id = ConversationID.test(1)

        try database.upsertConversationMessages([textMessage(id: 1)], conversationID: id)
        try database.upsertConversationMessages([textMessage(id: 1, at: 99)], conversationID: id)

        let loaded = try database.getConversationMessages(conversationID: id)
        #expect(loaded == [textMessage(id: 1, at: 99)])
    }

    @Test("Sub-second message dates round-trip exactly")
    func subSecondDateRoundTrip() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let id = ConversationID.test(1)
        let message = ConversationMessage(
            id: MessageID(value: 1),
            senderID: otherID,
            content: .text("hi"),
            date: Date(timeIntervalSinceReferenceDate: 800_000_000.123456),
            unreadSeq: 1
        )

        try database.upsertConversationMessages([message], conversationID: id)

        #expect(try database.getConversationMessages(conversationID: id) == [message])
    }

    @Test("Pruning keeps the newest window once the slack is exceeded")
    func pruneKeepsNewestWindow() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let id = ConversationID.test(1)
        let overflow = Database.messageWindow + Database.messageWindowSlack + 10

        try database.upsertConversationMessages(
            (1...UInt64(overflow)).map { textMessage(id: $0) },
            conversationID: id
        )

        let kept = try database.getConversationMessages(conversationID: id)
        #expect(kept.count == Database.messageWindow)
        #expect(kept.first?.id.value == UInt64(overflow - Database.messageWindow + 1))
        #expect(kept.last?.id.value == UInt64(overflow))
    }

    @Test("No pruning within the hysteresis slack")
    func pruneRespectsSlack() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let id = ConversationID.test(1)
        let withinSlack = Database.messageWindow + Database.messageWindowSlack

        try database.upsertConversationMessages(
            (1...UInt64(withinSlack)).map { textMessage(id: $0) },
            conversationID: id
        )

        #expect(try database.getConversationMessages(conversationID: id).count == withinSlack)
    }

    @Test("Pruning leaves other conversations and the feed preview intact")
    func pruneIsScopedAndPreviewSurvives() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let pruned = ConversationID.test(1)
        let untouched = ConversationID.test(2)
        let overflow = Database.messageWindow + Database.messageWindowSlack + 1

        try database.upsertConversation(conversation(byte: 1))
        try database.upsertConversation(conversation(byte: 2))
        try database.upsertConversationMessages(
            (1...UInt64(overflow)).map { textMessage(id: $0) },
            conversationID: pruned
        )
        try database.upsertConversationMessages([textMessage(id: 1)], conversationID: untouched)

        #expect(try database.getConversationMessages(conversationID: untouched).map(\.id.value) == [1])
        let previews = try database.getConversations().map(\.lastMessage?.id.value)
        #expect(previews.contains(UInt64(overflow)))
    }

    @Test("Messages are scoped to their conversation")
    func messagesAreScoped() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        try database.upsertConversationMessages([textMessage(id: 1)], conversationID: ConversationID.test(1))
        try database.upsertConversationMessages([textMessage(id: 2)], conversationID: ConversationID.test(2))

        #expect(try database.getConversationMessages(conversationID: ConversationID.test(1)).map(\.id.value) == [1])
        #expect(try database.getConversationMessages(conversationID: ConversationID.test(2)).map(\.id.value) == [2])
    }

    // MARK: - Conversations -

    @Test("A conversation round-trips with members, read pointers, and the newest message as preview")
    func conversationRoundTrip() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let members = [
            ConversationMember(userID: selfID, displayName: "Self", readPointer: MessageID(value: 1)),
            ConversationMember(userID: otherID, displayName: "Them", readPointer: nil),
        ]
        let preview = textMessage(id: 2, at: 60)
        let stored = conversation(byte: 1, members: members, lastMessage: preview)

        try database.upsertConversation(stored)
        try database.upsertConversationMessages([textMessage(id: 1, at: 30)], conversationID: stored.id)

        let loaded = try #require(try database.getConversations().first)
        #expect(loaded.id == stored.id)
        #expect(loaded.members == members)
        #expect(loaded.lastActivity == stored.lastActivity)
        #expect(loaded.lastMessage == preview)
    }

    @Test("A conversation with no stored messages loads a nil preview")
    func conversationWithoutMessages() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        try database.upsertConversation(conversation(byte: 1))

        let loaded = try #require(try database.getConversations().first)
        #expect(loaded.lastMessage == nil)
    }

    @Test("Re-upserting a conversation replaces its members wholesale")
    func memberReplacement() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let id = ConversationID.test(1)
        try database.upsertConversation(conversation(byte: 1, members: [
            ConversationMember(userID: selfID, displayName: "Self", readPointer: nil),
            ConversationMember(userID: otherID, displayName: "Them", readPointer: nil),
        ]))

        let advanced = [
            ConversationMember(userID: selfID, displayName: "Self", readPointer: MessageID(value: 9)),
            ConversationMember(userID: otherID, displayName: "Renamed", readPointer: nil),
        ]
        try database.upsertConversation(conversation(byte: 1, members: advanced))

        let loaded = try #require(try database.getConversations().first)
        #expect(loaded.id == id)
        #expect(loaded.members == advanced)
    }

    @Test("The feed loads most-recent activity first")
    func feedOrdering() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        try database.upsertConversation(conversation(byte: 1, lastActivity: Date(timeIntervalSince1970: 100)))
        try database.upsertConversation(conversation(byte: 2, lastActivity: Date(timeIntervalSince1970: 200)))

        #expect(try database.getConversations().map(\.id) == [ConversationID.test(2), ConversationID.test(1)])
    }

    // MARK: - Feed replace -

    @Test("Replacing the feed drops absent conversations and prunes their messages")
    func feedReplacePrunes() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        try database.upsertConversation(conversation(byte: 1))
        try database.upsertConversation(conversation(byte: 2))
        try database.upsertConversationMessages([textMessage(id: 1)], conversationID: ConversationID.test(1))
        try database.upsertConversationMessages([textMessage(id: 2)], conversationID: ConversationID.test(2))

        try database.replaceConversationFeed([conversation(byte: 1)])

        #expect(try database.getConversations().map(\.id) == [ConversationID.test(1)])
        #expect(try database.getConversationMessages(conversationID: ConversationID.test(1)).map(\.id.value) == [1])
        #expect(try database.getConversationMessages(conversationID: ConversationID.test(2)).isEmpty)
    }

    @Test("Replacing with an empty feed clears the cache")
    func emptyFeedReplaceClears() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        try database.upsertConversation(conversation(byte: 1))
        try database.upsertConversationMessages([textMessage(id: 1)], conversationID: ConversationID.test(1))

        try database.replaceConversationFeed([])

        #expect(try database.getConversations().isEmpty)
        #expect(try database.getConversationMessages(conversationID: ConversationID.test(1)).isEmpty)
    }
}
