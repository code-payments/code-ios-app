//
//  RecipientListItemTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite("Recipient list items")
struct RecipientListItemTests {

    private func contact(_ name: String, dmChatID: Data? = nil) -> ResolvedContact {
        ResolvedContact(
            contactId: "contact-\(name)",
            displayName: name,
            phoneE164: "+1555\(name.count)",
            nationalPhone: "(555) \(name.count)",
            imageData: nil,
            dmChatID: dmChatID
        )
    }

    private func conversation(byte: UInt8, lastActivity: Date) -> Conversation {
        Conversation(
            id: ConversationID(data: Data(repeating: byte, count: 32)),
            members: [],
            lastMessage: nil,
            lastActivity: lastActivity
        )
    }

    @Test("A contact joins its feed conversation into a matched Recents row")
    func contactJoinsConversation() {
        let chat = conversation(byte: 0x01, lastActivity: .now)
        let matched = contact("Anna", dmChatID: chat.id.data)

        let result = RecipientListItem.partition(
            contacts: [matched, contact("Ben")],
            conversations: [chat],
            searchText: "",
            conversationNames: [:]
        )

        #expect(result.recents == [.matched(matched, chat)])
        #expect(result.onFlipcash == [.contact(contact("Ben"))])
    }

    @Test("Recents rows sort by activity, newest first")
    func recentsSortByActivity() {
        let older = conversation(byte: 0x01, lastActivity: Date(timeIntervalSince1970: 100))
        let newer = conversation(byte: 0x02, lastActivity: Date(timeIntervalSince1970: 200))
        let first = contact("Anna", dmChatID: older.id.data)
        let second = contact("Ben", dmChatID: newer.id.data)

        let result = RecipientListItem.partition(
            contacts: [first, second],
            conversations: [older, newer],
            searchText: "",
            conversationNames: [:]
        )

        #expect(result.recents == [.matched(second, newer), .matched(first, older)])
        #expect(result.onFlipcash.isEmpty)
    }

    @Test("Chat-less contacts land in On Flipcash in directory order")
    func chatlessContactsInOnFlipcash() {
        let chat = conversation(byte: 0x01, lastActivity: .now)
        let matched = contact("Zoe", dmChatID: chat.id.data)

        let result = RecipientListItem.partition(
            contacts: [contact("Anna"), matched, contact("Ben")],
            conversations: [chat],
            searchText: "",
            conversationNames: [:]
        )

        #expect(result.recents == [.matched(matched, chat)])
        #expect(result.onFlipcash == [.contact(contact("Anna")), .contact(contact("Ben"))])
    }

    @Test("A conversation without a synced contact is a Recents row")
    func unmatchedConversationInRecents() {
        let older = conversation(byte: 0x01, lastActivity: Date(timeIntervalSince1970: 100))
        let newer = conversation(byte: 0x02, lastActivity: Date(timeIntervalSince1970: 200))
        let matched = contact("Anna", dmChatID: older.id.data)

        let result = RecipientListItem.partition(
            contacts: [matched],
            conversations: [older, newer],
            searchText: "",
            conversationNames: [:]
        )

        #expect(result.recents == [.conversation(newer), .matched(matched, older)])
        #expect(result.onFlipcash.isEmpty)
    }

    @Test("A pre-assigned chat ID with no feed conversation stays in On Flipcash")
    func preassignedChatIDStaysOnFlipcash() {
        let preassigned = contact("Anna", dmChatID: Data(repeating: 0x09, count: 32))

        let result = RecipientListItem.partition(
            contacts: [preassigned],
            conversations: [],
            searchText: "",
            conversationNames: [:]
        )

        #expect(result.recents.isEmpty)
        #expect(result.onFlipcash == [.contact(preassigned)])
    }

    @Test("Searching keeps an unmatched conversation whose chat name matches")
    func searchKeepsMatchingUnmatchedConversation() {
        let chat = conversation(byte: 0x05, lastActivity: .now)

        let result = RecipientListItem.partition(
            contacts: [],
            conversations: [chat],
            searchText: "ali",
            conversationNames: [chat.id: "Alice"]
        )

        #expect(result.recents == [.conversation(chat)])
    }

    @Test("Searching drops an unmatched conversation whose chat name doesn't match")
    func searchDropsNonMatchingUnmatchedConversation() {
        let chat = conversation(byte: 0x06, lastActivity: .now)

        let result = RecipientListItem.partition(
            contacts: [],
            conversations: [chat],
            searchText: "zzz",
            conversationNames: [chat.id: "Alice"]
        )

        #expect(result.recents.isEmpty)
    }

    @Test("Searching keeps a matched contact's conversation regardless of chat name")
    func searchKeepsMatchedContactConversation() {
        let chat = conversation(byte: 0x07, lastActivity: .now)
        let matched = contact("Anna", dmChatID: chat.id.data)

        let result = RecipientListItem.partition(
            contacts: [matched],
            conversations: [chat],
            searchText: "ann",
            conversationNames: [:]
        )

        #expect(result.recents == [.matched(matched, chat)])
    }
}
