//
//  ConversationUnreadTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import FlipcashCore

@Suite("Conversation unread state")
struct ConversationUnreadTests {

    private let selfID = UUID()
    private let otherID = UUID()

    private func conversation(
        lastMessageID: UInt64?,
        readPointer: UInt64?,
        otherReadPointer: UInt64? = nil
    ) -> Conversation {
        Conversation(
            id: ConversationID(data: Data(repeating: 0x01, count: 32)),
            members: [
                ConversationMember(
                    userID: selfID,
                    displayName: "Self",
                    readPointer: readPointer.map(MessageID.init(value:))
                ),
                ConversationMember(
                    userID: otherID,
                    displayName: "Them",
                    readPointer: otherReadPointer.map(MessageID.init(value:))
                ),
            ],
            lastMessage: lastMessageID.map { id in
                ConversationMessage(
                    id: MessageID(value: id),
                    senderID: otherID,
                    content: .text("hello"),
                    date: .now,
                    unreadSeq: id
                )
            },
            lastActivity: .now
        )
    }

    @Test("No messages is never unread")
    func emptyConversationIsRead() {
        let conversation = conversation(lastMessageID: nil, readPointer: nil)
        #expect(conversation.hasUnread(for: selfID) == false)
    }

    @Test("A message with no READ watermark is unread")
    func missingPointerIsUnread() {
        let conversation = conversation(lastMessageID: 1, readPointer: nil)
        #expect(conversation.hasUnread(for: selfID) == true)
    }

    @Test("A message past the READ watermark is unread")
    func newerMessageIsUnread() {
        let conversation = conversation(lastMessageID: 5, readPointer: 4)
        #expect(conversation.hasUnread(for: selfID) == true)
    }

    @Test("A message at the READ watermark is read")
    func watermarkMessageIsRead() {
        let conversation = conversation(lastMessageID: 5, readPointer: 5)
        #expect(conversation.hasUnread(for: selfID) == false)
    }

    @Test("A watermark past the last message is read")
    func aheadWatermarkIsRead() {
        let conversation = conversation(lastMessageID: 5, readPointer: 9)
        #expect(conversation.hasUnread(for: selfID) == false)
    }

    @Test("The counterpart's watermark doesn't count for the signed-in user")
    func otherMembersPointerIsIgnored() {
        let conversation = conversation(lastMessageID: 5, readPointer: nil, otherReadPointer: 5)
        #expect(conversation.hasUnread(for: selfID) == true)
    }
}
