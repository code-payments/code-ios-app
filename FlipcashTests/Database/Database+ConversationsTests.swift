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

    private func conversationID(_ byte: UInt8) -> ConversationID {
        ConversationID(data: Data(repeating: byte, count: 32))
    }

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
            id: conversationID(byte),
            members: members,
            lastMessage: lastMessage,
            lastActivity: lastActivity
        )
    }

    // MARK: - Messages -

    @Test("Text and cash messages round-trip, oldest first")
    func messagesRoundTrip() throws {
        let database = try Database.makeTemp()
        let id = conversationID(1)
        let messages = [textMessage(id: 2, at: 60), cashMessage(id: 3), textMessage(id: 1, at: 30)]

        try database.upsertConversationMessages(messages, conversationID: id)

        let loaded = try database.getConversationMessages(conversationID: id)
        #expect(loaded == [textMessage(id: 1, at: 30), textMessage(id: 2, at: 60), cashMessage(id: 3)])
    }

    @Test("Re-upserting a message id replaces the row instead of duplicating it")
    func messageUpsertReplaces() throws {
        let database = try Database.makeTemp()
        let id = conversationID(1)

        try database.upsertConversationMessages([textMessage(id: 1)], conversationID: id)
        try database.upsertConversationMessages([textMessage(id: 1, at: 99)], conversationID: id)

        let loaded = try database.getConversationMessages(conversationID: id)
        #expect(loaded == [textMessage(id: 1, at: 99)])
    }

    @Test("Messages are scoped to their conversation")
    func messagesAreScoped() throws {
        let database = try Database.makeTemp()
        try database.upsertConversationMessages([textMessage(id: 1)], conversationID: conversationID(1))
        try database.upsertConversationMessages([textMessage(id: 2)], conversationID: conversationID(2))

        #expect(try database.getConversationMessages(conversationID: conversationID(1)).map(\.id.value) == [1])
        #expect(try database.getConversationMessages(conversationID: conversationID(2)).map(\.id.value) == [2])
    }

    // MARK: - Conversations -

    @Test("A conversation round-trips with members, read pointers, and the newest message as preview")
    func conversationRoundTrip() throws {
        let database = try Database.makeTemp()
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
        let database = try Database.makeTemp()
        try database.upsertConversation(conversation(byte: 1))

        let loaded = try #require(try database.getConversations().first)
        #expect(loaded.lastMessage == nil)
    }

    @Test("Re-upserting a conversation replaces its members wholesale")
    func memberReplacement() throws {
        let database = try Database.makeTemp()
        let id = conversationID(1)
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
        let database = try Database.makeTemp()
        try database.upsertConversation(conversation(byte: 1, lastActivity: Date(timeIntervalSince1970: 100)))
        try database.upsertConversation(conversation(byte: 2, lastActivity: Date(timeIntervalSince1970: 200)))

        #expect(try database.getConversations().map(\.id) == [conversationID(2), conversationID(1)])
    }

    // MARK: - Feed replace -

    @Test("Replacing the feed drops absent conversations and prunes their messages")
    func feedReplacePrunes() throws {
        let database = try Database.makeTemp()
        try database.upsertConversation(conversation(byte: 1))
        try database.upsertConversation(conversation(byte: 2))
        try database.upsertConversationMessages([textMessage(id: 1)], conversationID: conversationID(1))
        try database.upsertConversationMessages([textMessage(id: 2)], conversationID: conversationID(2))

        try database.replaceConversationFeed([conversation(byte: 1)])

        #expect(try database.getConversations().map(\.id) == [conversationID(1)])
        #expect(try database.getConversationMessages(conversationID: conversationID(1)).map(\.id.value) == [1])
        #expect(try database.getConversationMessages(conversationID: conversationID(2)).isEmpty)
    }

    @Test("Replacing with an empty feed clears the cache")
    func emptyFeedReplaceClears() throws {
        let database = try Database.makeTemp()
        try database.upsertConversation(conversation(byte: 1))
        try database.upsertConversationMessages([textMessage(id: 1)], conversationID: conversationID(1))

        try database.replaceConversationFeed([])

        #expect(try database.getConversations().isEmpty)
        #expect(try database.getConversationMessages(conversationID: conversationID(1)).isEmpty)
    }
}
