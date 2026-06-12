//
//  ConversationControllerTests.swift
//  FlipcashTests
//

import Testing
import Foundation
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("ConversationController")
struct ConversationControllerTests {

    private func conversationID(_ byte: UInt8) -> ConversationID {
        ConversationID(data: Data(repeating: byte, count: 32))
    }

    /// Polls briefly for work the controller runs on its own task (stream
    /// consumption, feed paging) to land. Gives up after ~1s.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<50 where !condition() {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func makeController(
        _ mock: MockConversations,
        selfUserID: UserID = UUID(),
        naming: MockDMContactNaming = MockDMContactNaming()
    ) -> ConversationController {
        ConversationController(
            fetching: mock, messaging: mock, streaming: mock,
            contactNaming: naming,
            owner: .generate()!, selfUserID: selfUserID
        )
    }

    @Test("loadFeed populates conversations sorted by activity")
    func loadFeed() async {
        let mock = MockConversations()
        mock.feed = [
            Conversation(id: conversationID(1), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 100)),
            Conversation(id: conversationID(2), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 200)),
        ]
        let controller = makeController(mock)
        await controller.loadFeed()
        #expect(controller.conversations.map(\.id) == [conversationID(2), conversationID(1)])
    }

    @Test("send records the message and appends it to the conversation")
    func send() async {
        let mock = MockConversations()
        mock.sendResult = ConversationMessage(id: MessageID(value: 7), senderID: nil, content: .text("hello"), date: Date(timeIntervalSince1970: 0), unreadSeq: 0)
        let controller = makeController(mock)

        let ok = await controller.send("hello", to: conversationID(1))
        #expect(ok)
        #expect(mock.sent.map(\.text) == ["hello"])
        #expect(controller.messages(for: conversationID(1)).map(\.id.value) == [7])
    }

    @Test("markRead advances to the latest loaded message")
    func markRead() async {
        let mock = MockConversations()
        mock.messages = [ConversationMessage(id: MessageID(value: 5), senderID: nil, content: .text("x"), date: Date(timeIntervalSince1970: 0), unreadSeq: 0)]
        let controller = makeController(mock)

        await controller.loadMessages(for: conversationID(1))
        await controller.markRead(conversationID: conversationID(1))
        #expect(mock.markedRead == [MessageID(value: 5)])
    }

    @Test("markRead is skipped when the READ watermark already covers the latest message")
    func markReadSkipsWhenAlreadyRead() async {
        let me = UUID()
        let mock = MockConversations()
        mock.feed = [Conversation(
            id: conversationID(1),
            members: [
                ConversationMember(userID: me, displayName: "", readPointer: MessageID(value: 5)),
                ConversationMember(userID: UUID(), displayName: "Alice"),
            ],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0)
        )]
        mock.messages = [ConversationMessage(id: MessageID(value: 5), senderID: nil, content: .text("x"), date: Date(timeIntervalSince1970: 0), unreadSeq: 0)]
        let controller = makeController(mock, selfUserID: me)

        await controller.loadFeed()
        await controller.loadMessages(for: conversationID(1))
        await controller.markRead(conversationID: conversationID(1))
        #expect(mock.markedRead.isEmpty)
    }

    @Test("markRead fires for a newer message, then short-circuits after advancing")
    func markReadFiresThenSkips() async {
        let me = UUID()
        let mock = MockConversations()
        mock.feed = [Conversation(
            id: conversationID(1),
            members: [
                ConversationMember(userID: me, displayName: "", readPointer: MessageID(value: 3)),
                ConversationMember(userID: UUID(), displayName: "Alice"),
            ],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0)
        )]
        mock.messages = [ConversationMessage(id: MessageID(value: 5), senderID: nil, content: .text("x"), date: Date(timeIntervalSince1970: 0), unreadSeq: 0)]
        let controller = makeController(mock, selfUserID: me)

        await controller.loadFeed()
        await controller.loadMessages(for: conversationID(1))
        await controller.markRead(conversationID: conversationID(1))
        await controller.markRead(conversationID: conversationID(1))
        #expect(mock.markedRead == [MessageID(value: 5)])
    }

    @Test("uses the counterpart's feed-provided display name as the title")
    func counterpartName() async {
        let me = UUID()
        let other = UUID()
        let mock = MockConversations()
        mock.feed = [Conversation(
            id: conversationID(1),
            members: [ConversationMember(userID: me, displayName: ""), ConversationMember(userID: other, displayName: "Alice")],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0)
        )]
        let controller = makeController(mock, selfUserID: me)

        await controller.loadFeed()
        #expect(controller.displayName(forConversationID: conversationID(1)) == "Alice")
    }

    @Test("falls back to a generic title when the counterpart has no name")
    func counterpartNameFallback() async {
        let me = UUID()
        let other = UUID()
        let mock = MockConversations()
        mock.feed = [Conversation(
            id: conversationID(1),
            members: [ConversationMember(userID: me, displayName: ""), ConversationMember(userID: other, displayName: "")],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0)
        )]
        let controller = makeController(mock, selfUserID: me)

        await controller.loadFeed()
        #expect(controller.displayName(forConversationID: conversationID(1)) == "Flipcash User")
    }

    @Test("prefers the synced contact's address-book name over the member name")
    func contactNameWinsOverMemberName() async {
        let me = UUID()
        let mock = MockConversations()
        mock.feed = [Conversation(
            id: conversationID(1),
            members: [ConversationMember(userID: me, displayName: ""), ConversationMember(userID: UUID(), displayName: "Alice")],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0)
        )]
        let naming = MockDMContactNaming()
        naming.names = [conversationID(1): "Alice Appleseed"]
        let controller = makeController(mock, selfUserID: me, naming: naming)

        await controller.loadFeed()
        #expect(controller.displayName(forConversationID: conversationID(1)) == "Alice Appleseed")
    }

    @Test("resolves the contact name for a conversation not yet in the feed")
    func contactNameWithoutFeedConversation() {
        let naming = MockDMContactNaming()
        naming.names = [conversationID(2): "Bob"]
        let controller = makeController(MockConversations(), naming: naming)

        #expect(controller.displayName(forConversationID: conversationID(2)) == "Bob")
        #expect(controller.displayName(forConversationID: conversationID(3)) == "Flipcash User")
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

        let message = ConversationMessage(id: MessageID(value: 9), senderID: nil, content: .text("live"), date: Date(timeIntervalSince1970: 0), unreadSeq: 0)
        mock.emit(.newMessages(conversationID: conversationID(1), messages: [message]))

        // The stream is consumed on a Task; poll briefly for it to apply.
        await waitUntil { !controller.messages(for: conversationID(1)).isEmpty }
        #expect(controller.messages(for: conversationID(1)).map(\.id.value) == [9])
        controller.stop()
    }

    @Test("a streamed message for an unknown conversation hydrates it into the feed at the top")
    func hydratesUnknownConversation() async {
        let mock = MockConversations()
        let existing = Conversation(id: conversationID(1), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 100))
        mock.feed = [existing]
        let controller = makeController(mock)

        controller.start()
        // start() pages the feed on its own task; wait for it before scripting
        // the new chat so the assertion isolates the hydration.
        await waitUntil { !controller.conversations.isEmpty }
        #expect(controller.conversations.map(\.id) == [conversationID(1)])

        // A brand-new chat (created by a first payment) starts streaming
        // before the loaded feed knows it; getChat resolves it server-side.
        let newConversation = Conversation(
            id: conversationID(2), members: [],
            lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 200)
        )
        mock.feed = [existing, newConversation]
        let message = ConversationMessage(id: MessageID(value: 1), senderID: nil, content: .text("first"), date: Date(timeIntervalSince1970: 200), unreadSeq: 0)
        mock.emit(.newMessages(conversationID: conversationID(2), messages: [message]))

        // The stream is consumed on a Task; poll briefly for the hydration.
        await waitUntil { controller.conversations.count >= 2 }
        #expect(controller.conversations.map(\.id) == [conversationID(2), conversationID(1)])
        controller.stop()
    }
}
