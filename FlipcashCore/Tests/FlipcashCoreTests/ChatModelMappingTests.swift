//
//  ChatModelMappingTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashAPI
@testable import FlipcashCore

@Suite("Chat model proto mapping")
struct ChatModelMappingTests {

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

        let message = try #require(ChatMessage(proto))
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
        #expect(ChatMessage(proto) == nil)
    }

    @Test("DM metadata maps chat id, last message, and last activity")
    func dmMetadataMaps() {
        let chatBytes = Data(repeating: 0xAB, count: 32)
        let proto = Flipcash_Chat_V1_Metadata.with {
            $0.chatID = .with { $0.value = chatBytes }
            $0.type = .dm
            $0.lastActivity = .init(date: Date(timeIntervalSince1970: 1_700_000_500))
            $0.lastMessage = .with {
                $0.messageID = .with { $0.value = 9 }
                $0.content = [.with { $0.text = .with { $0.text = "last" } }]
            }
        }

        let chat = Conversation(proto)
        #expect(chat.id == ChatID(data: chatBytes))
        #expect(chat.lastMessage?.text == "last")
        #expect(chat.lastActivity == Date(timeIntervalSince1970: 1_700_000_500))
    }

    @Test("Counterpart excludes the signed-in user")
    func counterpartExcludesSelf() {
        let me = UUID()
        let other = UUID()
        let chat = Conversation(
            id: ChatID(data: Data(repeating: 0x01, count: 32)),
            members: [
                ChatMember(userID: me, displayName: "Me"),
                ChatMember(userID: other, displayName: "Alice"),
            ],
            lastMessage: nil,
            lastActivity: .now
        )

        #expect(chat.counterpart(excluding: me)?.userID == other)
    }
}
