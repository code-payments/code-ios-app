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
        case .text, .deleted:
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

    @Test("Re-upserting a message id replaces the row with a newer version instead of duplicating it")
    func messageUpsertReplaces() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let id = ConversationID.test(1)

        // Last-writer-wins: a strictly-newer event_sequence replaces the row in place (no duplicate);
        // an equal version is kept (covered by the identity tests below).
        let first = ConversationMessage(id: MessageID(value: 1), senderID: otherID, content: .text("first"),
            date: Date(timeIntervalSince1970: 0), unreadSeq: 1, eventSequence: 1)
        let newer = ConversationMessage(id: MessageID(value: 1), senderID: otherID, content: .text("second"),
            date: Date(timeIntervalSince1970: 99), unreadSeq: 1, eventSequence: 2)
        try database.upsertConversationMessages([first], conversationID: id)
        try database.upsertConversationMessages([newer], conversationID: id)

        let loaded = try database.getConversationMessages(conversationID: id)
        #expect(loaded.count == 1)          // no duplicate
        #expect(loaded == [newer])          // newer version won
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

    @Test("Retains all history — no prune")
    func retainsAllHistory() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let id = ConversationID.test(1)
        let count = Database.messageWindow * 3

        try database.upsertConversationMessages(
            (1...UInt64(count)).map { textMessage(id: $0) },
            conversationID: id
        )

        let all = try database.getConversationMessages(conversationID: id)
        #expect(all.count == count)                    // nothing pruned
        #expect(all.first?.id.value == 1)
        #expect(all.last?.id.value == UInt64(count))
    }

    @Test("A windowed read returns the newest N, oldest-first")
    func windowedReadReturnsNewest() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let id = ConversationID.test(1)
        let count = 250

        try database.upsertConversationMessages(
            (1...UInt64(count)).map { textMessage(id: $0) },
            conversationID: id
        )

        let window = try database.getConversationMessages(conversationID: id, newest: Database.messageWindow)
        #expect(window.count == Database.messageWindow)
        #expect(window.first?.id.value == UInt64(count - Database.messageWindow + 1))   // oldest-first
        #expect(window.last?.id.value == UInt64(count))                                  // newest at the tail
    }

    @Test("History is retained per conversation and the feed preview is the newest message")
    func historyScopedAndPreviewSurvives() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let heavy = ConversationID.test(1)
        let light = ConversationID.test(2)
        let count = Database.messageWindow * 2

        try database.upsertConversation(conversation(byte: 1))
        try database.upsertConversation(conversation(byte: 2))
        try database.upsertConversationMessages(
            (1...UInt64(count)).map { textMessage(id: $0) },
            conversationID: heavy
        )
        try database.upsertConversationMessages([textMessage(id: 1)], conversationID: light)

        #expect(try database.getConversationMessages(conversationID: heavy).count == count)   // retained
        #expect(try database.getConversationMessages(conversationID: light).map(\.id.value) == [1])
        let previews = try database.getConversations().map(\.lastMessage?.id.value)
        #expect(previews.contains(UInt64(count)))
    }

    // MARK: - Identity + atomicity

    @Test("clientMessageID round-trips through the cache")
    func clientMessageIDRoundTrips() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let clientID = UUID()
        let message = ConversationMessage(
            id: MessageID(value: 5), senderID: selfID, content: .text("hi"),
            date: Date(timeIntervalSince1970: 0), unreadSeq: 5, clientMessageID: clientID
        )
        try database.upsertConversationMessages([message], conversationID: ConversationID.test(1))
        #expect(try database.getConversationMessages(conversationID: ConversationID.test(1)).first?.clientMessageID == clientID)
    }

    @Test("equal eventSequence adopts a missing client id without changing content")
    func equalSequenceAdoptsClientID() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let id = ConversationID.test(1)
        let stored = ConversationMessage(id: MessageID(value: 5), senderID: selfID, content: .text("hi"),
            date: Date(timeIntervalSince1970: 0), unreadSeq: 5, eventSequence: 3)
        try database.upsertConversationMessages([stored], conversationID: id)
        // An equal-version copy carrying the client id (a reconcile landing after the stream echo).
        let clientID = UUID()
        let echo = ConversationMessage(id: MessageID(value: 5), senderID: selfID, content: .text("hi"),
            date: Date(timeIntervalSince1970: 0), unreadSeq: 5, eventSequence: 3, clientMessageID: clientID)
        try database.upsertConversationMessages([echo], conversationID: id)
        let row = try database.getConversationMessages(conversationID: id).first
        #expect(row?.clientMessageID == clientID)   // adopted
        #expect(row?.content == .text("hi"))         // content unchanged
    }

    @Test("a newer version preserves the stored client id when it lacks one")
    func newerVersionPreservesClientID() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let id = ConversationID.test(1)
        let clientID = UUID()
        let stored = ConversationMessage(id: MessageID(value: 5), senderID: selfID, content: .text("hi"),
            date: Date(timeIntervalSince1970: 0), unreadSeq: 5, eventSequence: 3, clientMessageID: clientID)
        try database.upsertConversationMessages([stored], conversationID: id)
        // A newer edit arrives with no client id (the server never echoes it).
        let edit = ConversationMessage(id: MessageID(value: 5), senderID: selfID, content: .text("edited"),
            date: Date(timeIntervalSince1970: 0), unreadSeq: 5, eventSequence: 4)
        try database.upsertConversationMessages([edit], conversationID: id)
        let row = try database.getConversationMessages(conversationID: id).first
        #expect(row?.content == .text("edited"))    // newer content won
        #expect(row?.clientMessageID == clientID)   // identity preserved
    }

    // Proves the batch + cursor both land on success. The rollback-on-partial-failure half of
    // atomicity is guaranteed by the single `writer.transaction`, but isn't unit-exercisable without a
    // DB fault-injection hook (which would be production test-support), so it stands by construction.
    @Test("persistMessages writes the batch and advances the cursor together")
    func persistMessagesAdvancesCursorAtomically() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let id = ConversationID.test(1)
        try database.upsertConversation(conversation(byte: 1))   // the cursor lives on the conversation row
        try database.persistMessages([textMessage(id: 5), textMessage(id: 6)], cursor: 42, conversationID: id)
        #expect(try database.getConversationMessages(conversationID: id).map(\.id.value) == [5, 6])
        #expect(try database.getCatchupCursors()[id] == 42)
    }

    @Test("persistMessages does not write an unestablished (zero) cursor")
    func persistMessagesSkipsZeroCursor() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let id = ConversationID.test(1)
        try database.upsertConversation(conversation(byte: 1))
        try database.persistMessages([textMessage(id: 5)], cursor: 0, conversationID: id)
        #expect(try database.getConversationMessages(conversationID: id).map(\.id.value) == [5])
        #expect(try database.getCatchupCursors()[id] == nil)   // nothing written
    }

    @Test("catchupCursor round-trips the persisted cursor for one conversation")
    func catchupCursorRoundTrips() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let id = ConversationID.test(1)
        try database.upsertConversation(conversation(byte: 1))
        #expect(try database.catchupCursor(conversationID: id) == 0)   // none yet
        try database.persistMessages([textMessage(id: 5)], cursor: 42, conversationID: id)
        #expect(try database.catchupCursor(conversationID: id) == 42)
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

    // MARK: - Event log persistence -

    @Test("event_sequence and a deleted tombstone round-trip")
    func eventSequenceAndTombstoneRoundTrip() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let id = ConversationID.test(1)
        let text = ConversationMessage(id: MessageID(value: 1), senderID: otherID, content: .text("hi"), date: Date(timeIntervalSince1970: 10), unreadSeq: 1, eventSequence: 7)
        let tombstone = ConversationMessage(id: MessageID(value: 2), senderID: otherID, content: .deleted, date: Date(timeIntervalSince1970: 20), unreadSeq: 2, eventSequence: 9)

        try database.upsertConversationMessages([text, tombstone], conversationID: id)

        let loaded = try database.getConversationMessages(conversationID: id)
        #expect(loaded == [text, tombstone])
        #expect(loaded.map(\.eventSequence) == [7, 9])
        #expect(loaded.last?.content == .deleted)
    }

    @Test("the catch-up cursor round-trips and survives a feed replace")
    func catchupCursorRoundTrip() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let id = ConversationID.test(1)
        try database.upsertConversation(conversation(byte: 1))
        try database.updateCatchupCursor(42, for: id)
        #expect(try database.getCatchupCursors()[id] == 42)

        // A feed replace deletes+reinserts every conversation row but must preserve the cursor.
        try database.replaceConversationFeed([conversation(byte: 1)])
        #expect(try database.getCatchupCursors()[id] == 42)
    }

    @Test("a stale re-delivery does not clobber a newer persisted version (DB last-writer-wins)")
    func writeMessageIsLastWriterWins() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let id = ConversationID.test(1)
        let tombstone = ConversationMessage(id: MessageID(value: 1), senderID: otherID, content: .deleted, date: Date(timeIntervalSince1970: 20), unreadSeq: 1, eventSequence: 10)
        let staleOriginal = ConversationMessage(id: MessageID(value: 1), senderID: otherID, content: .text("original"), date: Date(timeIntervalSince1970: 10), unreadSeq: 1, eventSequence: 5)

        try database.upsertConversationMessages([tombstone], conversationID: id)
        try database.upsertConversationMessages([staleOriginal], conversationID: id) // older version → ignored

        let loaded = try database.getConversationMessages(conversationID: id)
        #expect(loaded.count == 1)
        #expect(loaded.first?.content == .deleted)   // tombstone survives the stale re-delivery
        #expect(loaded.first?.eventSequence == 10)

        // A genuinely newer version still wins.
        let newer = ConversationMessage(id: MessageID(value: 1), senderID: otherID, content: .text("edited"), date: Date(timeIntervalSince1970: 30), unreadSeq: 1, eventSequence: 12)
        try database.upsertConversationMessages([newer], conversationID: id)
        #expect(try database.getConversationMessages(conversationID: id).first?.content == .text("edited"))
    }

    @Test("the feed preview skips a deleted newest message and shows the newest visible one")
    func latestMessageSkipsTombstone() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        try database.upsertConversation(conversation(byte: 1))
        let visible = ConversationMessage(id: MessageID(value: 1), senderID: otherID, content: .text("hello"), date: Date(timeIntervalSince1970: 10), unreadSeq: 1, eventSequence: 1)
        let deletedNewest = ConversationMessage(id: MessageID(value: 2), senderID: otherID, content: .deleted, date: Date(timeIntervalSince1970: 20), unreadSeq: 2, eventSequence: 5)
        try database.upsertConversationMessages([visible, deletedNewest], conversationID: ConversationID.test(1))

        let loaded = try #require(try database.getConversations().first)
        #expect(loaded.lastMessage?.content == .text("hello")) // preview shows the visible message, not the tombstone
    }

    // MARK: - Conversations -

    @Test("A conversation round-trips with members, phone numbers, read pointers, and the newest message as preview")
    func conversationRoundTrip() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let members = [
            ConversationMember(userID: selfID, displayName: "Self", readPointer: MessageID(value: 1)),
            ConversationMember(userID: otherID, displayName: "Them", phoneE164: "+14155550100", readPointer: nil),
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
