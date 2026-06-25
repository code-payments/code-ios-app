//
//  RecipientFeedOrderTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite("Recipient feed order")
struct RecipientFeedOrderTests {

    private func contact(
        _ name: String,
        id: String? = nil,
        phone: String? = nil,
        dmChatID: Data? = nil,
        joinDate: Date? = nil
    ) -> ResolvedContact {
        ResolvedContact(
            contactId: id ?? "contact-\(name)",
            displayName: name,
            phoneE164: phone ?? "+1555\(name.count)",
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

    private let order = RecipientFeedOrder()

    @Test("A more recent row precedes an older one")
    func recencyOrdersMostRecentFirst() {
        let recent = RecipientListItem.conversation(conversation(byte: 0x01, lastActivity: Date(timeIntervalSince1970: 200)))
        let older = RecipientListItem.conversation(conversation(byte: 0x02, lastActivity: Date(timeIntervalSince1970: 100)))

        #expect(order.compare(recent, older) == .orderedAscending)
        #expect(order.compare(older, recent) == .orderedDescending)
    }

    @Test("Recency is the more recent of conversation activity and join date")
    func recencyUsesLaterOfActivityAndJoin() {
        let chat = conversation(byte: 0x01, lastActivity: Date(timeIntervalSince1970: 300))
        // Matched row ranks by its activity (300), not the contact's earlier join (100).
        let matched = RecipientListItem.matched(
            contact("Anna", dmChatID: chat.id.data, joinDate: Date(timeIntervalSince1970: 100)),
            chat
        )
        // Chat-less contact ranks by its join date (200).
        let newcomer = RecipientListItem.contact(contact("Ben", joinDate: Date(timeIntervalSince1970: 200)))

        #expect(order.compare(matched, newcomer) == .orderedAscending)
    }

    @Test("Rows sharing a date tie-break by name, ascending")
    func equalDateTieBreaksByName() {
        let joined = Date(timeIntervalSince1970: 200)
        let anna = RecipientListItem.contact(contact("Anna", joinDate: joined))
        let zoe = RecipientListItem.contact(contact("Zoe", joinDate: joined))

        #expect(order.compare(anna, zoe) == .orderedAscending)
        #expect(order.compare(zoe, anna) == .orderedDescending)
    }

    @Test("Rows sharing date and name fall back to the unique id")
    func equalDateAndNameTieBreakByID() {
        let joined = Date(timeIntervalSince1970: 200)
        let first = RecipientListItem.contact(contact("Sam", id: "id-1", phone: "+15550001", joinDate: joined))
        let second = RecipientListItem.contact(contact("Sam", id: "id-2", phone: "+15550002", joinDate: joined))

        // Same date, same name, distinct ids → ordered by id so the result is total.
        #expect(order.compare(first, second) == .orderedAscending)
        #expect(order.compare(second, first) == .orderedDescending)
    }

    @Test("A row compares equal to itself")
    func reflexive() {
        let item = RecipientListItem.contact(contact("Anna", joinDate: Date(timeIntervalSince1970: 200)))

        #expect(order.compare(item, item) == .orderedSame)
    }

    @Test("Reverse order flips the comparison")
    func reverseOrderFlips() {
        let recent = RecipientListItem.conversation(conversation(byte: 0x01, lastActivity: Date(timeIntervalSince1970: 200)))
        let older = RecipientListItem.conversation(conversation(byte: 0x02, lastActivity: Date(timeIntervalSince1970: 100)))
        let reversed = RecipientFeedOrder(order: .reverse)

        #expect(reversed.compare(recent, older) == .orderedDescending)
        #expect(reversed.compare(older, recent) == .orderedAscending)
    }
}
