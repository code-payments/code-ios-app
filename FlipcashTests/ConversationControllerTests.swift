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
        database: Database? = nil,
        typingHeartbeatInterval: Duration = .seconds(3),
        incomingTypingExpiry: Duration = .seconds(10)
    ) -> ConversationController {
        ConversationController(
            fetching: mock, messaging: mock, streaming: mock,
            contactNaming: naming,
            database: database ?? (try! Database.makeTemp().database),
            owner: .generate()!, selfUserID: selfUserID,
            typingHeartbeatInterval: typingHeartbeatInterval,
            incomingTypingExpiry: incomingTypingExpiry
        )
    }

    @Test("a received typing notification marks the counterpart typing; self is ignored")
    func receivesTyping() async throws {
        let me = UUID(), them = UUID()
        let mock = MockConversations()
        let controller = makeController(mock, selfUserID: me)
        controller.start()
        try await waitUntil { mock.streamOpened }

        mock.emit(.typingChanged(conversationID: .test(1), notifications: [
            TypingNotification(userID: them, isActive: true),
            TypingNotification(userID: me, isActive: true),
        ]))
        try await waitUntil { controller.isCounterpartTyping(in: .test(1)) }
        #expect(controller.isCounterpartTyping(in: .test(1)))
    }

    @Test("a stopped notification clears the typing state")
    func stopsTyping() async throws {
        let them = UUID()
        let mock = MockConversations()
        let controller = makeController(mock)
        controller.start()
        try await waitUntil { mock.streamOpened }

        mock.emit(.typingChanged(conversationID: .test(1), notifications: [TypingNotification(userID: them, isActive: true)]))
        try await waitUntil { controller.isCounterpartTyping(in: .test(1)) }
        mock.emit(.typingChanged(conversationID: .test(1), notifications: [TypingNotification(userID: them, isActive: false)]))
        try await waitUntil { !controller.isCounterpartTyping(in: .test(1)) }
        #expect(!controller.isCounterpartTyping(in: .test(1)))
    }

    @Test("a non-empty draft sends STARTED once; clearing it sends STOPPED")
    func sendsTypingOnDraft() async throws {
        let mock = MockConversations()
        let controller = makeController(mock)

        controller.draftDidChange("h", in: .test(1))
        try await waitUntil { mock.typingCalls.contains { $0.state == .started } }
        controller.draftDidChange("", in: .test(1))
        try await waitUntil { mock.typingCalls.contains { $0.state == .stopped } }

        let states = mock.typingCalls.map(\.state)
        #expect(states.filter { $0 == .started }.count == 1)
        #expect(states.last == .stopped)
    }

    @Test("stopSelfTyping sends STOPPED only when currently typing")
    func stopSelfTypingGuarded() async throws {
        let mock = MockConversations()
        let controller = makeController(mock)

        controller.stopSelfTyping(in: .test(1))
        #expect(mock.typingCalls.isEmpty)

        controller.draftDidChange("hey", in: .test(1))
        try await waitUntil { mock.typingCalls.contains { $0.state == .started } }
        controller.stopSelfTyping(in: .test(1))
        try await waitUntil { mock.typingCalls.contains { $0.state == .stopped } }
        #expect(mock.typingCalls.last?.state == .stopped)
    }

    @Test("clearing the draft before the typing task starts sends nothing and doesn't wedge typing")
    func draftClearedBeforeTaskStarts() async throws {
        let mock = MockConversations()
        let controller = makeController(mock)

        // Both calls run synchronously before the scheduled task body can take the MainActor, so the
        // clear cancels the typing task before it ever runs — the exact fast type-then-clear race.
        controller.draftDidChange("h", in: .test(1))
        controller.draftDidChange("", in: .test(1))
        try await Task.sleep(for: .milliseconds(50))
        #expect(mock.typingCalls.isEmpty) // no orphaned STARTED

        // Typing must still work afterward (state not wedged true).
        controller.draftDidChange("hi", in: .test(1))
        try await waitUntil { mock.typingCalls.contains { $0.state == .started } }
        #expect(mock.typingCalls.contains { $0.state == .started })
    }

    @Test("an active typist expires locally when no further notification arrives")
    func typistExpiresWithoutStop() async throws {
        let them = UUID()
        let mock = MockConversations()
        let controller = makeController(mock, incomingTypingExpiry: .milliseconds(200))
        controller.start()
        try await waitUntil { mock.streamOpened }

        mock.emit(.typingChanged(conversationID: .test(1), notifications: [TypingNotification(userID: them, isActive: true)]))
        try await waitUntil { controller.isCounterpartTyping(in: .test(1)) }
        // The STOPPED never arrives (dropped by the best-effort relay); the local
        // expiry must clear the indicator on its own.
        try await waitUntil { !controller.isCounterpartTyping(in: .test(1)) }
    }

    @Test("a refreshed typing notification extends the expiry window")
    func typingRefreshExtendsExpiry() async throws {
        let them = UUID()
        let mock = MockConversations()
        let controller = makeController(mock, incomingTypingExpiry: .milliseconds(500))
        controller.start()
        try await waitUntil { mock.streamOpened }

        mock.emit(.typingChanged(conversationID: .test(1), notifications: [TypingNotification(userID: them, isActive: true)]))
        try await waitUntil { controller.isCounterpartTyping(in: .test(1)) }

        // A STILL ~300ms in pushes the deadline to ~800ms; at ~600ms the original
        // 500ms deadline has passed but the refreshed one hasn't.
        try await Task.sleep(for: .milliseconds(300))
        mock.emit(.typingChanged(conversationID: .test(1), notifications: [TypingNotification(userID: them, isActive: true)]))
        try await Task.sleep(for: .milliseconds(300))
        #expect(controller.isCounterpartTyping(in: .test(1)))

        try await waitUntil { !controller.isCounterpartTyping(in: .test(1)) }
    }

    @Test("a STOPPED never overtakes an in-flight earlier send")
    func typingSendsStayOrdered() async throws {
        let mock = MockConversations()
        mock.typingDelays = [.started: .milliseconds(200)]
        let controller = makeController(mock)

        controller.draftDidChange("h", in: .test(1))
        // Let the STARTED enter the (slow) transport before clearing the draft.
        try await Task.sleep(for: .milliseconds(50))
        controller.draftDidChange("", in: .test(1))

        try await waitUntil { mock.typingCalls.count == 2 }
        #expect(mock.typingCalls.map(\.state) == [.started, .stopped])
    }

    @Test("a rapid stop-then-restart coalesces to the latest state")
    func typingBurstCoalesces() async throws {
        let mock = MockConversations()
        mock.typingDelays = [.started: .milliseconds(200)]
        let controller = makeController(mock)

        controller.draftDidChange("h", in: .test(1))
        try await Task.sleep(for: .milliseconds(50))
        // While the STARTED is still in flight: clear (queues STOPPED) then type
        // again. States are absolute, so the queued STOPPED is superseded — the
        // wire only ever needs the latest state.
        controller.draftDidChange("", in: .test(1))
        controller.draftDidChange("i", in: .test(1))

        try await waitUntil { mock.typingCalls.count == 2 }
        // Give any extra (non-coalesced) sends time to land before pinning the sequence.
        try await Task.sleep(for: .milliseconds(250))
        #expect(mock.typingCalls.map(\.state) == [.started, .started])
    }

    @Test("STILL heartbeats fire while the user keeps typing without pausing")
    func heartbeatDuringContinuousTyping() async throws {
        let mock = MockConversations()
        let controller = makeController(mock, typingHeartbeatInterval: .milliseconds(300))

        // Keystrokes every ~30ms for ~600ms — never a 300ms pause, so a purely
        // pause-driven loop would stay silent after the initial STARTED.
        var draft = ""
        for _ in 0..<20 {
            draft += "a"
            controller.draftDidChange(draft, in: .test(1))
            try await Task.sleep(for: .milliseconds(30))
        }
        #expect(mock.typingCalls.map(\.state).contains(.still))
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

    @Test("send shows the message immediately as sending, then sent on success")
    func sendOptimisticSuccess() async {
        let me = UUID()
        let mock = MockConversations()
        mock.sendResult = ConversationMessage(id: MessageID(value: 7), senderID: me, content: .text("hello"), date: Date(timeIntervalSince1970: 0), unreadSeq: 0)
        let controller = makeController(mock, selfUserID: me)

        let ok = await controller.send("hello", to: ConversationID.test(1))
        #expect(ok)
        let messages = controller.messages(for: ConversationID.test(1))
        #expect(messages.count == 1)
        #expect(messages.first?.id.value == 7)
        #expect(messages.first?.status == .sent)
    }

    @Test("a failed send leaves the message in the transcript as failed")
    func sendOptimisticFailureKeepsMessage() async {
        let me = UUID()
        let mock = MockConversations()
        mock.sendError = ErrorSendMessage.transportFailure
        let controller = makeController(mock, selfUserID: me)

        let ok = await controller.send("hello", to: ConversationID.test(1))
        #expect(!ok)
        let messages = controller.messages(for: ConversationID.test(1))
        #expect(messages.count == 1)
        #expect(messages.first?.status == .failed)
        #expect(messages.first?.content == .text("hello"))
    }

    @Test("retry re-sends the failed message reusing its client id")
    func retryReusesClientID() async throws {
        let me = UUID()
        let mock = MockConversations()
        mock.sendError = ErrorSendMessage.transportFailure
        let controller = makeController(mock, selfUserID: me)
        _ = await controller.send("hello", to: ConversationID.test(1))

        let failed = try #require(controller.messages(for: ConversationID.test(1)).first)
        let clientID = try #require(failed.clientMessageID)

        // Second attempt succeeds.
        mock.sendError = nil
        mock.sendResult = ConversationMessage(id: MessageID(value: 9), senderID: me, content: .text("hello"), date: Date(timeIntervalSince1970: 0), unreadSeq: 0)
        await controller.retry(clientMessageID: clientID, in: ConversationID.test(1))

        #expect(mock.sentClientIDs == [clientID, clientID])   // same id both attempts → server-idempotent
        let messages = controller.messages(for: ConversationID.test(1))
        #expect(messages.count == 1)
        #expect(messages.first?.status == .sent)
        #expect(messages.first?.id.value == 9)
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

    // MARK: - Reconnect catch-up -

    @Test("a reconnect catches up the visible conversation via GetDelta, filling messages missed while the stream was down")
    func reconnectCatchesUpVisibleTranscript() async throws {
        let mock = MockConversations()
        mock.feed = [Conversation(id: ConversationID.test(1), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 100))]
        mock.messages = [ConversationMessage(id: MessageID(value: 1), senderID: nil, content: .text("one"), date: Date(timeIntervalSince1970: 10), unreadSeq: 1, eventSequence: 1)]
        let controller = makeController(mock)

        controller.start()
        try await waitUntil { mock.connectionStateStreamOpened }
        // The initial connection's first `.live` is the baseline — no gap to fill.
        mock.emitConnectionState(.live)

        // Open the chat: load its first page and mark it visible (as the screen does).
        await controller.loadMessages(for: ConversationID.test(1))
        controller.visibleConversationID = ConversationID.test(1)
        try #require(controller.messages(for: ConversationID.test(1)).map(\.id.value) == [1])

        // The missed message is delivered by the reconnect catch-up (GetDelta), not a blind page reload.
        mock.deltaBatches = [MockConversations.DeltaBatch(
            messages: [ConversationMessage(id: MessageID(value: 2), senderID: nil, content: .text("two"), date: Date(timeIntervalSince1970: 20), unreadSeq: 2, eventSequence: 2)],
            checkpoint: 2
        )]
        mock.deltaHead = 2

        // The stream drops and comes back: the reconnect's `.live` triggers catch-up.
        mock.emitConnectionState(.disconnected)
        mock.emitConnectionState(.live)

        try await waitUntil { controller.messages(for: ConversationID.test(1)).map(\.id.value) == [1, 2] }
        // loadMessages seated the frontier to the newest loaded message's eventSequence (1), so the
        // reconnect catch-up resumes from there — not a from-zero full refetch.
        #expect(mock.deltaAfterSequences == [1])
        controller.stop()
    }

    @Test("foreground catches up the open chat via GetDelta with no ping (missed-message-on-unlock regression)")
    func foregroundCatchUpFillsOpenTranscript() async throws {
        let mock = MockConversations()
        mock.feed = [Conversation(id: ConversationID.test(1), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 100))]
        mock.messages = [ConversationMessage(id: MessageID(value: 1), senderID: nil, content: .text("one"), date: Date(timeIntervalSince1970: 10), unreadSeq: 1, eventSequence: 1)]
        let controller = makeController(mock)

        controller.start()
        try await waitUntil { mock.connectionStateStreamOpened }
        await controller.loadMessages(for: ConversationID.test(1))
        controller.visibleConversationID = ConversationID.test(1)
        try #require(controller.messages(for: ConversationID.test(1)).map(\.id.value) == [1])

        // A message arrived while the phone was locked (stream suspended); no ping, no live event.
        mock.deltaBatches = [MockConversations.DeltaBatch(
            messages: [ConversationMessage(id: MessageID(value: 2), senderID: nil, content: .text("locked while away"), date: Date(timeIntervalSince1970: 20), unreadSeq: 2, eventSequence: 2)],
            checkpoint: 2
        )]
        mock.deltaHead = 2

        // Unlock → foreground. No stream reconnect, no ping — the open transcript still fills.
        controller.catchUpOpenChat()

        try await waitUntil { controller.messages(for: ConversationID.test(1)).map(\.id.value) == [1, 2] }
        controller.stop()
    }

    @Test("RESET_REQUIRED discards the cursor and re-syncs history via GetMessages")
    func catchUpResetResyncsHistory() async throws {
        let mock = MockConversations()
        mock.feed = [Conversation(id: ConversationID.test(1), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 100))]
        let controller = makeController(mock)

        controller.start()
        try await waitUntil { mock.connectionStateStreamOpened }
        controller.visibleConversationID = ConversationID.test(1)

        // The cursor is too far behind: GetDelta returns RESET_REQUIRED, so catch-up falls back to the
        // newest page and re-establishes the cursor from that page's floor.
        mock.deltaError = ErrorGetDelta.resetRequired
        mock.messages = [
            ConversationMessage(id: MessageID(value: 8), senderID: nil, content: .text("h8"), date: Date(timeIntervalSince1970: 80), unreadSeq: 8, eventSequence: 8),
            ConversationMessage(id: MessageID(value: 9), senderID: nil, content: .text("h9"), date: Date(timeIntervalSince1970: 90), unreadSeq: 9, eventSequence: 9),
        ]

        await controller.catchUp(conversationID: ConversationID.test(1))

        #expect(controller.messages(for: ConversationID.test(1)).map(\.id.value) == [8, 9])
        #expect(mock.latestPageQueries == [ConversationID.test(1)]) // re-synced the newest page
        controller.stop()
    }

    @Test("loadMessages seats the cursor to the newest page's head, so catch-up resumes from there (no from-zero full refetch that would prepend history)")
    func loadMessagesSeatsCursorToHead() async throws {
        let mock = MockConversations()
        mock.feed = [Conversation(id: ConversationID.test(1), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 100))]
        mock.messages = [ConversationMessage(id: MessageID(value: 9), senderID: nil, content: .text("newest"), date: Date(timeIntervalSince1970: 90), unreadSeq: 9, eventSequence: 42)]
        let controller = makeController(mock)
        controller.start()
        try await waitUntil { mock.streamOpened }

        await controller.loadMessages(for: ConversationID.test(1))
        await controller.catchUp(conversationID: ConversationID.test(1))
        // Resumes from the seated head (42), NOT 0 — the from-zero refetch is what re-pulled the full
        // history and knocked the transcript off the bottom on first open.
        #expect(mock.deltaAfterSequences == [42])
        controller.stop()
    }

    @Test("a reconnect refreshes the feed even with no conversation open")
    func reconnectRefreshesFeed() async throws {
        let mock = MockConversations()
        let controller = makeController(mock)

        controller.start()
        try await waitUntil { mock.connectionStateStreamOpened }
        try await waitUntil { controller.conversations.isEmpty }
        mock.emitConnectionState(.live)   // initial connection — baseline

        // The feed gains a conversation while the stream was down.
        mock.feed = [Conversation(id: ConversationID.test(1), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 100))]
        mock.emitConnectionState(.disconnected)
        mock.emitConnectionState(.live)   // reconnect → refetch

        try await waitUntil { controller.conversations.map(\.id) == [ConversationID.test(1)] }
        controller.stop()
    }

    @Test("a reconnect with no conversation open refreshes the feed but fetches no transcript")
    func reconnectWithoutVisibleConversationSkipsMessages() async throws {
        let mock = MockConversations()
        let controller = makeController(mock)

        controller.start()
        try await waitUntil { mock.connectionStateStreamOpened }
        mock.emitConnectionState(.live)   // initial connection — baseline

        // No conversation is visible. The feed refresh proves the refetch ran;
        // the transcript page must not be fetched.
        mock.feed = [Conversation(id: ConversationID.test(1), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 100))]
        mock.emitConnectionState(.disconnected)
        mock.emitConnectionState(.live)   // reconnect → loadFeed only

        try await waitUntil { controller.conversations.map(\.id) == [ConversationID.test(1)] }
        #expect(mock.latestPageQueries.isEmpty)
        #expect(mock.deltaAfterSequences.isEmpty) // no visible chat → no catch-up
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
