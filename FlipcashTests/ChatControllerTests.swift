//
//  ChatControllerTests.swift
//  FlipcashTests
//

import Testing
import Foundation
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("ChatController")
struct ChatControllerTests {

    private func chatID(_ byte: UInt8) -> ChatID {
        ChatID(data: Data(repeating: byte, count: 32))
    }

    private func makeController(_ mock: MockConversations, selfUserID: UserID = UUID()) -> ChatController {
        ChatController(
            fetching: mock, messaging: mock, streaming: mock,
            owner: .generate()!, selfUserID: selfUserID
        )
    }

    @Test("loadFeed populates conversations sorted by activity")
    func loadFeed() async {
        let mock = MockConversations()
        mock.feed = [
            Conversation(id: chatID(1), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 100)),
            Conversation(id: chatID(2), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 200)),
        ]
        let controller = makeController(mock)
        await controller.loadFeed()
        #expect(controller.conversations.map(\.id) == [chatID(2), chatID(1)])
    }

    @Test("send records the message and appends it to the conversation")
    func send() async {
        let mock = MockConversations()
        mock.sendResult = ChatMessage(id: MessageID(value: 7), senderID: nil, text: "hello", date: Date(timeIntervalSince1970: 0), unreadSeq: 0)
        let controller = makeController(mock)

        let ok = await controller.send("hello", to: chatID(1))
        #expect(ok)
        #expect(mock.sent.map(\.text) == ["hello"])
        #expect(controller.messages(for: chatID(1)).map(\.id.value) == [7])
    }

    @Test("markRead advances to the latest loaded message")
    func markRead() async {
        let mock = MockConversations()
        mock.messages = [ChatMessage(id: MessageID(value: 5), senderID: nil, text: "x", date: Date(timeIntervalSince1970: 0), unreadSeq: 0)]
        let controller = makeController(mock)

        await controller.loadMessages(for: chatID(1))
        await controller.markRead(chatID: chatID(1))
        #expect(mock.markedRead == [MessageID(value: 5)])
    }

    @Test("markRead is skipped when the READ watermark already covers the latest message")
    func markReadSkipsWhenAlreadyRead() async {
        let me = UUID()
        let mock = MockConversations()
        mock.feed = [Conversation(
            id: chatID(1),
            members: [
                ChatMember(userID: me, displayName: "", readPointer: MessageID(value: 5)),
                ChatMember(userID: UUID(), displayName: "Alice"),
            ],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0)
        )]
        mock.messages = [ChatMessage(id: MessageID(value: 5), senderID: nil, text: "x", date: Date(timeIntervalSince1970: 0), unreadSeq: 0)]
        let controller = makeController(mock, selfUserID: me)

        await controller.loadFeed()
        await controller.loadMessages(for: chatID(1))
        await controller.markRead(chatID: chatID(1))
        #expect(mock.markedRead.isEmpty)
    }

    @Test("markRead fires for a newer message, then short-circuits after advancing")
    func markReadFiresThenSkips() async {
        let me = UUID()
        let mock = MockConversations()
        mock.feed = [Conversation(
            id: chatID(1),
            members: [
                ChatMember(userID: me, displayName: "", readPointer: MessageID(value: 3)),
                ChatMember(userID: UUID(), displayName: "Alice"),
            ],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0)
        )]
        mock.messages = [ChatMessage(id: MessageID(value: 5), senderID: nil, text: "x", date: Date(timeIntervalSince1970: 0), unreadSeq: 0)]
        let controller = makeController(mock, selfUserID: me)

        await controller.loadFeed()
        await controller.loadMessages(for: chatID(1))
        await controller.markRead(chatID: chatID(1))
        await controller.markRead(chatID: chatID(1))
        #expect(mock.markedRead == [MessageID(value: 5)])
    }

    @Test("uses the counterpart's feed-provided display name as the title")
    func counterpartName() async {
        let me = UUID()
        let other = UUID()
        let mock = MockConversations()
        mock.feed = [Conversation(
            id: chatID(1),
            members: [ChatMember(userID: me, displayName: ""), ChatMember(userID: other, displayName: "Alice")],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0)
        )]
        let controller = makeController(mock, selfUserID: me)

        await controller.loadFeed()
        #expect(controller.displayName(forChatID: chatID(1)) == "Alice")
    }

    @Test("falls back to a generic title when the counterpart has no name")
    func counterpartNameFallback() async {
        let me = UUID()
        let other = UUID()
        let mock = MockConversations()
        mock.feed = [Conversation(
            id: chatID(1),
            members: [ChatMember(userID: me, displayName: ""), ChatMember(userID: other, displayName: "")],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0)
        )]
        let controller = makeController(mock, selfUserID: me)

        await controller.loadFeed()
        #expect(controller.displayName(forChatID: chatID(1)) == "Flipcash User")
    }

    @Test("ensureConnected and stop route to the streaming surface")
    func lifecycle() async {
        let mock = MockConversations()
        let controller = makeController(mock)
        controller.ensureConnected()
        controller.stop()
        #expect(mock.didEnsure)
        #expect(mock.didClose)
    }

    @Test("a streamed event is applied to the conversation store")
    func appliesStreamedEvent() async {
        let mock = MockConversations()
        let controller = makeController(mock)
        controller.start()

        let message = ChatMessage(id: MessageID(value: 9), senderID: nil, text: "live", date: Date(timeIntervalSince1970: 0), unreadSeq: 0)
        mock.emit(.newMessages(chatID: chatID(1), messages: [message]))

        // The stream is consumed on a Task; poll briefly for it to apply.
        for _ in 0..<50 where controller.messages(for: chatID(1)).isEmpty {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(controller.messages(for: chatID(1)).map(\.id.value) == [9])
        controller.stop()
    }
}
