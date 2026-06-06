//
//  ConversationModelMappingTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashAPI
@testable import FlipcashCore

@Suite("Conversation model proto mapping")
struct ConversationModelMappingTests {

    @Test("Text message maps id, sender, content, timestamp, and unread sequence")
    func textMessageParses() throws {
        let senderUUID = UUID()
        let proto = Flipcash_Messaging_V1_Message.with {
            $0.messageID = .with { $0.value = 7 }
            $0.senderID = .with { $0.value = senderUUID.data }
            $0.content = [.with { $0.text = .with { $0.text = "hello" } }]
            $0.ts = .init(date: Date(timeIntervalSince1970: 1_700_000_000))
            $0.unreadSeq = 3
        }

        let message = try #require(ConversationMessage(proto))
        #expect(message.id == MessageID(value: 7))
        #expect(message.senderID == senderUUID)
        #expect(message.text == "hello")
        #expect(message.date == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(message.unreadSeq == 3)
    }

    @Test("Message with no text content returns nil")
    func nonTextReturnsNil() {
        let proto = Flipcash_Messaging_V1_Message.with {
            $0.messageID = .with { $0.value = 1 }
        }
        #expect(ConversationMessage(proto) == nil)
    }

    @Test("DM metadata maps conversation id, last message, and last activity")
    func dmMetadataMaps() {
        let conversationBytes = Data(repeating: 0xAB, count: 32)
        let proto = Flipcash_Chat_V1_Metadata.with {
            $0.chatID = .with { $0.value = conversationBytes }
            $0.type = .dm
            $0.lastActivity = .init(date: Date(timeIntervalSince1970: 1_700_000_500))
            $0.lastMessage = .with {
                $0.messageID = .with { $0.value = 9 }
                $0.content = [.with { $0.text = .with { $0.text = "last" } }]
            }
        }

        let conversation = Conversation(proto)
        #expect(conversation.id == ConversationID(data: conversationBytes))
        #expect(conversation.lastMessage?.text == "last")
        #expect(conversation.lastActivity == Date(timeIntervalSince1970: 1_700_000_500))
    }

    @Test("Counterpart excludes the signed-in user")
    func counterpartExcludesSelf() {
        let me = UUID()
        let other = UUID()
        let conversation = Conversation(
            id: ConversationID(data: Data(repeating: 0x01, count: 32)),
            members: [
                ConversationMember(userID: me, displayName: "Me"),
                ConversationMember(userID: other, displayName: "Alice"),
            ],
            lastMessage: nil,
            lastActivity: .now
        )

        #expect(conversation.counterpart(excluding: me)?.userID == other)
    }
}
