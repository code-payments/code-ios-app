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

    private func contact(_ name: String, dmChatID: Data? = nil, joinDate: Date? = nil) -> ResolvedContact {
        ResolvedContact(
            contactId: "contact-\(name)",
            displayName: name,
            phoneE164: "+1555\(name.count)",
            nationalPhone: "(555) \(name.count)",
            imageData: nil,
            dmChatID: dmChatID,
            joinDate: joinDate
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

    @Test("A contact joins its feed conversation into one matched row")
    func contactJoinsConversation() {
        let chat = conversation(byte: 0x01, lastActivity: .now)
        let matched = contact("Anna", dmChatID: chat.id.data)

        let items = RecipientListItem.items(contacts: [matched, contact("Ben")], conversations: [chat])

        #expect(items == [.matched(matched, chat), .contact(contact("Ben"))])
        #expect(items[0].id == matched.id)
    }

    @Test("Rows with conversations sort by activity, newest first")
    func activeRowsSortByActivity() {
        let older = conversation(byte: 0x01, lastActivity: Date(timeIntervalSince1970: 100))
        let newer = conversation(byte: 0x02, lastActivity: Date(timeIntervalSince1970: 200))
        let first = contact("Anna", dmChatID: older.id.data)
        let second = contact("Ben", dmChatID: newer.id.data)

        let items = RecipientListItem.items(contacts: [first, second], conversations: [older, newer])

        #expect(items == [.matched(second, newer), .matched(first, older)])
    }

    @Test("Chat-less contacts keep the directory's order, after active rows")
    func chatlessContactsKeepOrder() {
        let chat = conversation(byte: 0x01, lastActivity: .now)
        let matched = contact("Zoe", dmChatID: chat.id.data)

        let items = RecipientListItem.items(
            contacts: [contact("Anna"), matched, contact("Ben")],
            conversations: [chat]
        )

        #expect(items == [.matched(matched, chat), .contact(contact("Anna")), .contact(contact("Ben"))])
    }

    @Test("A conversation without a synced contact still gets a row")
    func unmatchedConversationIsIncluded() {
        let older = conversation(byte: 0x01, lastActivity: Date(timeIntervalSince1970: 100))
        let newer = conversation(byte: 0x02, lastActivity: Date(timeIntervalSince1970: 200))
        let matched = contact("Anna", dmChatID: older.id.data)

        let items = RecipientListItem.items(contacts: [matched], conversations: [older, newer])

        #expect(items == [.conversation(newer), .matched(matched, older)])
    }

    @Test("A pre-assigned chat ID with no feed conversation stays a contact row")
    func preassignedChatIDWithoutFeedStaysContact() {
        let preassigned = contact("Anna", dmChatID: Data(repeating: 0x09, count: 32))

        let items = RecipientListItem.items(contacts: [preassigned], conversations: [])

        #expect(items == [.contact(preassigned)])
    }

    @Test("A just-joined chat-less contact sorts above an older conversation")
    func chatlessContactSortsByJoinDate() {
        let oldChat = conversation(byte: 0x01, lastActivity: Date(timeIntervalSince1970: 100))
        let chatContact = contact("Anna", dmChatID: oldChat.id.data)
        let newcomer = contact("Ben", joinDate: Date(timeIntervalSince1970: 200))

        let items = RecipientListItem.items(contacts: [chatContact, newcomer], conversations: [oldChat])

        #expect(items == [.contact(newcomer), .matched(chatContact, oldChat)])
    }

    @Test("A matched row sorts by activity even when the contact joined earlier")
    func matchedRowSortsByActivityOverJoinDate() {
        let chat = conversation(byte: 0x01, lastActivity: Date(timeIntervalSince1970: 300))
        let longtime = contact("Anna", dmChatID: chat.id.data, joinDate: Date(timeIntervalSince1970: 100))
        let newcomer = contact("Ben", joinDate: Date(timeIntervalSince1970: 200))

        let items = RecipientListItem.items(contacts: [longtime, newcomer], conversations: [chat])

        #expect(items == [.matched(longtime, chat), .contact(newcomer)])
    }

    @Test("Chat-less contacts sharing a join date tie-break by name")
    func chatlessContactsTieBreakByName() {
        let joined = Date(timeIntervalSince1970: 200)
        let zoe = contact("Zoe", joinDate: joined)
        let anna = contact("Anna", joinDate: joined)

        let items = RecipientListItem.items(contacts: [zoe, anna], conversations: [])

        #expect(items == [.contact(anna), .contact(zoe)])
    }
}
