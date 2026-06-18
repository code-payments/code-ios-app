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

    /// Polls briefly for work the controller runs on its own task (stream
    /// consumption, feed paging) to land. Fails the test after ~1s.
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<50 where !condition() {
            try? await Task.sleep(for: .milliseconds(20))
        }
        try #require(condition(), "Timed out waiting for condition after ~1s")
    }

    private func makeController(
        _ mock: MockConversations,
        selfUserID: UserID = UUID(),
        naming: MockDMContactNaming = MockDMContactNaming(),
        database: Database? = nil
    ) -> ConversationController {
        ConversationController(
            fetching: mock, messaging: mock, streaming: mock,
            contactNaming: naming,
            database: database ?? (try! Database.makeTemp().database),
            owner: .generate()!, selfUserID: selfUserID
        )
    }


    @Test("loadFeed populates conversations sorted by activity")
    func loadFeed() async {
        let mock = MockConversations()
        mock.feed = [
            Conversation(id: ConversationID.test(1), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 100)),
            Conversation(id: ConversationID.test(2), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 200)),
        ]
        let controller = makeController(mock)
        await controller.loadFeed()
        #expect(controller.conversations.map(\.id) == [ConversationID.test(2), ConversationID.test(1)])
    }

    @Test("unreadConversationCount counts only conversations with unread messages")
    func unreadConversationCount() async {
        let me = UUID()
        let mock = MockConversations()
        mock.feed = [
            // Unread: last message is past the self read pointer.
            Conversation(
                id: ConversationID.test(1),
                members: [ConversationMember(userID: me, displayName: "", readPointer: MessageID(value: 1))],
                lastMessage: ConversationMessage(id: MessageID(value: 5), senderID: nil, content: .text("x"), date: Date(timeIntervalSince1970: 0), unreadSeq: 0),
                lastActivity: Date(timeIntervalSince1970: 400)
            ),
            // Read: the read pointer covers the last message.
            Conversation(
                id: ConversationID.test(2),
                members: [ConversationMember(userID: me, displayName: "", readPointer: MessageID(value: 5))],
                lastMessage: ConversationMessage(id: MessageID(value: 5), senderID: nil, content: .text("y"), date: Date(timeIntervalSince1970: 0), unreadSeq: 0),
                lastActivity: Date(timeIntervalSince1970: 300)
            ),
            // Empty: no last message is never unread.
            Conversation(
                id: ConversationID.test(3),
                members: [ConversationMember(userID: me, displayName: "")],
                lastMessage: nil,
                lastActivity: Date(timeIntervalSince1970: 200)
            ),
            // Unread: a message with no read pointer.
            Conversation(
                id: ConversationID.test(4),
                members: [ConversationMember(userID: me, displayName: "", readPointer: nil)],
                lastMessage: ConversationMessage(id: MessageID(value: 2), senderID: nil, content: .text("z"), date: Date(timeIntervalSince1970: 0), unreadSeq: 0),
                lastActivity: Date(timeIntervalSince1970: 100)
            ),
        ]
        let controller = makeController(mock, selfUserID: me)
        await controller.loadFeed()
        #expect(controller.unreadConversationCount == 2)
    }

    @Test("send records the message and appends it to the conversation")
    func send() async {
        let mock = MockConversations()
        mock.sendResult = ConversationMessage(id: MessageID(value: 7), senderID: nil, content: .text("hello"), date: Date(timeIntervalSince1970: 0), unreadSeq: 0)
        let controller = makeController(mock)

        let ok = await controller.send("hello", to: ConversationID.test(1))
        #expect(ok)
        #expect(mock.sent.map(\.text) == ["hello"])
        #expect(controller.messages(for: ConversationID.test(1)).map(\.id.value) == [7])
    }

    @Test("markRead advances to the latest loaded message")
    func markRead() async {
        let mock = MockConversations()
        mock.messages = [ConversationMessage(id: MessageID(value: 5), senderID: nil, content: .text("x"), date: Date(timeIntervalSince1970: 0), unreadSeq: 0)]
        let controller = makeController(mock)

        await controller.loadMessages(for: ConversationID.test(1))
        await controller.markRead(conversationID: ConversationID.test(1))
        #expect(mock.markedRead == [MessageID(value: 5)])
    }

    @Test("markRead is skipped when the READ watermark already covers the latest message")
    func markReadSkipsWhenAlreadyRead() async {
        let me = UUID()
        let mock = MockConversations()
        mock.feed = [Conversation(
            id: ConversationID.test(1),
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
        await controller.loadMessages(for: ConversationID.test(1))
        await controller.markRead(conversationID: ConversationID.test(1))
        #expect(mock.markedRead.isEmpty)
    }

    @Test("markRead fires for a newer message, then short-circuits after advancing")
    func markReadFiresThenSkips() async {
        let me = UUID()
        let mock = MockConversations()
        mock.feed = [Conversation(
            id: ConversationID.test(1),
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
        await controller.loadMessages(for: ConversationID.test(1))
        await controller.markRead(conversationID: ConversationID.test(1))
        await controller.markRead(conversationID: ConversationID.test(1))
        #expect(mock.markedRead == [MessageID(value: 5)])
    }

    @Test("uses the counterpart's feed-provided display name as the title")
    func counterpartName() async {
        let me = UUID()
        let other = UUID()
        let mock = MockConversations()
        mock.feed = [Conversation(
            id: ConversationID.test(1),
            members: [ConversationMember(userID: me, displayName: ""), ConversationMember(userID: other, displayName: "Alice")],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0)
        )]
        let controller = makeController(mock, selfUserID: me)

        await controller.loadFeed()
        #expect(controller.displayName(forConversationID: ConversationID.test(1)) == "Alice")
    }

    @Test("falls back to the counterpart's phone number when it has no name")
    func counterpartPhoneFallback() async {
        let me = UUID()
        let other = UUID()
        let mock = MockConversations()
        mock.feed = [Conversation(
            id: ConversationID.test(1),
            members: [
                ConversationMember(userID: me, displayName: ""),
                ConversationMember(userID: other, displayName: "", phoneE164: "+14155550100"),
            ],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0)
        )]
        let controller = makeController(mock, selfUserID: me)

        await controller.loadFeed()
        #expect(controller.displayName(forConversationID: ConversationID.test(1)) == "(415) 555-0100")
    }

    @Test("falls back to a generic title when the counterpart has no name or phone")
    func counterpartNameFallback() async {
        let me = UUID()
        let other = UUID()
        let mock = MockConversations()
        mock.feed = [Conversation(
            id: ConversationID.test(1),
            members: [ConversationMember(userID: me, displayName: ""), ConversationMember(userID: other, displayName: "")],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0)
        )]
        let controller = makeController(mock, selfUserID: me)

        await controller.loadFeed()
        #expect(controller.displayName(forConversationID: ConversationID.test(1)) == "Flipcash User")
    }

    @Test("prefers the synced contact's address-book name over the member name")
    func contactNameWinsOverMemberName() async {
        let me = UUID()
        let mock = MockConversations()
        mock.feed = [Conversation(
            id: ConversationID.test(1),
            members: [ConversationMember(userID: me, displayName: ""), ConversationMember(userID: UUID(), displayName: "Alice")],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0)
        )]
        let naming = MockDMContactNaming()
        naming.names = [ConversationID.test(1): "Alice Appleseed"]
        let controller = makeController(mock, selfUserID: me, naming: naming)

        await controller.loadFeed()
        #expect(controller.displayName(forConversationID: ConversationID.test(1)) == "Alice Appleseed")
    }

    @Test("resolves the contact name for a conversation not yet in the feed")
    func contactNameWithoutFeedConversation() {
        let naming = MockDMContactNaming()
        naming.names = [ConversationID.test(2): "Bob"]
        let controller = makeController(MockConversations(), naming: naming)

        #expect(controller.displayName(forConversationID: ConversationID.test(2)) == "Bob")
        #expect(controller.displayName(forConversationID: ConversationID.test(3)) == "Flipcash User")
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
    func appliesStreamedEvent() async throws {
        let mock = MockConversations()
        let controller = makeController(mock)
        controller.start()
        // start() hydrates the cache before opening the stream; emitting
        // earlier would drop the event on the floor.
        try await waitUntil { mock.streamOpened }

        let message = ConversationMessage(id: MessageID(value: 9), senderID: nil, content: .text("live"), date: Date(timeIntervalSince1970: 0), unreadSeq: 0)
        mock.emit(.newMessages(conversationID: ConversationID.test(1), messages: [message]))

        // The stream is consumed on a Task; poll briefly for it to apply.
        try await waitUntil { !controller.messages(for: ConversationID.test(1)).isEmpty }
        #expect(controller.messages(for: ConversationID.test(1)).map(\.id.value) == [9])
        controller.stop()
    }

    @Test("a streamed message for an unknown conversation hydrates it into the feed at the top")
    func hydratesUnknownConversation() async throws {
        let mock = MockConversations()
        let existing = Conversation(id: ConversationID.test(1), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 100))
        mock.feed = [existing]
        let controller = makeController(mock)

        controller.start()
        // start() pages the feed on its own task; wait for it before scripting
        // the new chat so the assertion isolates the hydration.
        try await waitUntil { !controller.conversations.isEmpty }
        #expect(controller.conversations.map(\.id) == [ConversationID.test(1)])

        // A brand-new chat (created by a first payment) starts streaming
        // before the loaded feed knows it; getChat resolves it server-side.
        let newConversation = Conversation(
            id: ConversationID.test(2), members: [],
            lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 200)
        )
        mock.feed = [existing, newConversation]
        let message = ConversationMessage(id: MessageID(value: 1), senderID: nil, content: .text("first"), date: Date(timeIntervalSince1970: 200), unreadSeq: 0)
        mock.emit(.newMessages(conversationID: ConversationID.test(2), messages: [message]))

        // The stream is consumed on a Task; poll briefly for the hydration.
        try await waitUntil { controller.conversations.count >= 2 }
        #expect(controller.conversations.map(\.id) == [ConversationID.test(2), ConversationID.test(1)])
        controller.stop()
    }

    // MARK: - Pagination -

    @Test("loadOlderMessages pages before the oldest loaded id and prepends the page")
    func loadOlderMessagesPrepends() async {
        let mock = MockConversations()
        mock.messages = [
            ConversationMessage(id: MessageID(value: 5), senderID: nil, content: .text("e"), date: Date(timeIntervalSince1970: 50), unreadSeq: 5),
            ConversationMessage(id: MessageID(value: 6), senderID: nil, content: .text("f"), date: Date(timeIntervalSince1970: 60), unreadSeq: 6),
        ]
        mock.olderMessages = [
            ConversationMessage(id: MessageID(value: 3), senderID: nil, content: .text("c"), date: Date(timeIntervalSince1970: 30), unreadSeq: 3),
            ConversationMessage(id: MessageID(value: 4), senderID: nil, content: .text("d"), date: Date(timeIntervalSince1970: 40), unreadSeq: 4),
        ]
        let controller = makeController(mock)
        await controller.loadMessages(for: ConversationID.test(1))

        await controller.loadOlderMessages(for: ConversationID.test(1))

        // Paged strictly before the oldest loaded id, prepended oldest-first.
        #expect(mock.olderQueries == [MessageID(value: 5)])
        #expect(controller.messages(for: ConversationID.test(1)).map(\.id.value) == [3, 4, 5, 6])
        #expect(controller.hasMoreOlderMessages(for: ConversationID.test(1)))
    }

    @Test("an empty older page ends pagination and short-circuits further queries")
    func loadOlderMessagesExhausted() async {
        let mock = MockConversations()
        mock.messages = [ConversationMessage(id: MessageID(value: 5), senderID: nil, content: .text("e"), date: Date(timeIntervalSince1970: 50), unreadSeq: 5)]
        mock.olderMessages = []
        let controller = makeController(mock)
        await controller.loadMessages(for: ConversationID.test(1))

        await controller.loadOlderMessages(for: ConversationID.test(1))
        #expect(mock.olderQueries == [MessageID(value: 5)])
        #expect(!controller.hasMoreOlderMessages(for: ConversationID.test(1)))

        // Exhausted → a further call doesn't hit the network again.
        await controller.loadOlderMessages(for: ConversationID.test(1))
        #expect(mock.olderQueries == [MessageID(value: 5)])
    }

    @Test("loadOlderMessages no-ops when no messages are loaded yet")
    func loadOlderMessagesNoOpWhenEmpty() async {
        let mock = MockConversations()
        let controller = makeController(mock)

        await controller.loadOlderMessages(for: ConversationID.test(1))

        #expect(mock.olderQueries.isEmpty)
    }

    // MARK: - Persistence -

    @Test("hydration seeds the feed and transcripts from the database without any fetch")
    func hydratesFromDatabase() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let conversation = Conversation(
            id: ConversationID.test(1), members: [],
            lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 100)
        )
        try database.upsertConversation(conversation)
        try database.upsertConversationMessages(
            [
                ConversationMessage(id: MessageID(value: 1), senderID: nil, content: .text("hi"), date: Date(timeIntervalSince1970: 10), unreadSeq: 1),
                ConversationMessage(id: MessageID(value: 2), senderID: nil, content: .text("there"), date: Date(timeIntervalSince1970: 20), unreadSeq: 2),
            ],
            conversationID: ConversationID.test(1)
        )

        let controller = makeController(MockConversations(), database: database)

        // Init does no disk I/O — the store is empty until hydration runs.
        #expect(controller.conversations.isEmpty)

        await controller.hydrateFromDatabase()

        #expect(controller.conversations.map(\.id) == [ConversationID.test(1)])
        #expect(controller.messages(for: ConversationID.test(1)).map(\.id.value) == [1, 2])
    }

    @Test("loadFeed, loadMessages, and markRead persist — a fresh controller rehydrates the same state")
    func persistsAcrossControllers() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let selfUserID = UUID()
        let mock = MockConversations()
        mock.feed = [Conversation(
            id: ConversationID.test(1),
            members: [ConversationMember(userID: selfUserID, displayName: "Self", readPointer: nil)],
            lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 100)
        )]
        mock.messages = [
            ConversationMessage(id: MessageID(value: 1), senderID: nil, content: .text("hi"), date: Date(timeIntervalSince1970: 10), unreadSeq: 1),
            ConversationMessage(id: MessageID(value: 2), senderID: nil, content: .text("there"), date: Date(timeIntervalSince1970: 20), unreadSeq: 2),
        ]
        let controller = makeController(mock, selfUserID: selfUserID, database: database)
        await controller.loadFeed()
        await controller.loadMessages(for: ConversationID.test(1))
        await controller.markRead(conversationID: ConversationID.test(1))

        let freshDatabase = try Database(url: url)
        let rehydrated = makeController(MockConversations(), selfUserID: selfUserID, database: freshDatabase)
        await rehydrated.hydrateFromDatabase()

        #expect(rehydrated.conversations.map(\.id) == [ConversationID.test(1)])
        #expect(rehydrated.messages(for: ConversationID.test(1)).map(\.id.value) == [1, 2])
        let pointer = rehydrated.conversations.first?.selfReadPointer(for: selfUserID)
        #expect(pointer == MessageID(value: 2))
    }
}
