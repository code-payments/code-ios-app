//
//  ConversationControllerTests.swift
//  FlipcashTests
//

import Testing
import Foundation
import FlipcashCore
import FlipcashStore
@testable import Flipcash

@MainActor
@Suite("ConversationController")
struct ConversationControllerTests {

    /// Polls briefly for work the controller runs on its own task (stream
    /// consumption, feed paging) to land. Fails the test after ~1s.
    private func waitUntil(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        for _ in 0..<50 where !condition() {
            try? await Task.sleep(for: .milliseconds(20))
        }
        try #require(condition(), "Timed out waiting for condition after ~1s", sourceLocation: sourceLocation)
    }

    private func makeController(
        _ mock: MockConversations,
        selfUserID: UserID = UUID(),
        naming: MockDMContactNaming = MockDMContactNaming(),
        database: Database? = nil,
        typingHeartbeatInterval: Duration = .seconds(3),
        incomingTypingExpiry: Duration = .seconds(10),
        typingExpiryClock: TypingExpiryClock = .continuous
    ) -> ConversationController {
        ConversationController(
            fetching: mock, membership: mock, viewerSettings: mock, messaging: mock, streaming: mock,
            contactNaming: naming,
            database: database ?? (try! Database.makeTemp().database),
            owner: .generate()!, selfUserID: selfUserID,
            typingHeartbeatInterval: typingHeartbeatInterval,
            incomingTypingExpiry: incomingTypingExpiry,
            typingExpiryClock: typingExpiryClock
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
        let clock = ManualTypingClock()
        let controller = makeController(mock, incomingTypingExpiry: .milliseconds(200), typingExpiryClock: clock.clock)
        controller.start()
        try await waitUntil { mock.streamOpened }

        mock.emit(.typingChanged(conversationID: .test(1), notifications: [TypingNotification(userID: them, isActive: true)]))
        try await waitUntil { controller.isCounterpartTyping(in: .test(1)) }
        // The STOPPED never arrives (dropped by the best-effort relay); the local
        // expiry must clear the indicator on its own.
        clock.advance(by: .milliseconds(200))
        try await waitUntil { !controller.isCounterpartTyping(in: .test(1)) }
    }

    @Test("a refreshed typing notification extends the expiry window")
    func typingRefreshExtendsExpiry() async throws {
        let them = UUID()
        let mock = MockConversations()
        let clock = ManualTypingClock()
        let controller = makeController(mock, incomingTypingExpiry: .milliseconds(500), typingExpiryClock: clock.clock)
        controller.start()
        try await waitUntil { mock.streamOpened }

        mock.emit(.typingChanged(conversationID: .test(1), notifications: [TypingNotification(userID: them, isActive: true)]))
        try await waitUntil { controller.isCounterpartTyping(in: .test(1)) }

        clock.advance(by: .milliseconds(150))
        mock.emit(.typingChanged(conversationID: .test(1), notifications: [TypingNotification(userID: them, isActive: true)]))
        // Waiting for the re-armed sweep is what makes the next check hold: once it is parked on
        // the new deadline, nothing is left to fire at the original one.
        try await waitUntil { clock.nextDeadline == .milliseconds(650) }

        clock.advance(by: .milliseconds(350))
        #expect(controller.isCounterpartTyping(in: .test(1)), "the typist must outlive its original deadline")

        clock.advance(by: .milliseconds(150))
        try await waitUntil { !controller.isCounterpartTyping(in: .test(1)) }
    }

    @Test("typists list oldest to newest, and a heartbeat keeps a typist's place")
    func typists_heartbeatFromOldest_keepsStartOrder() async throws {
        let a = UUID(), b = UUID(), c = UUID()
        let mock = MockConversations()
        let controller = makeController(mock)
        controller.start()
        try await waitUntil { mock.streamOpened }

        for (index, typist) in [a, b, c].enumerated() {
            mock.emit(.typingChanged(conversationID: .test(1), notifications: [TypingNotification(userID: typist, isActive: true)]))
            try await waitUntil { controller.typists(in: .test(1)).count == index + 1 }
        }
        #expect(controller.typists(in: .test(1)) == [a, b, c])

        // A STILL from the oldest typist extends their deadline without moving them to the back.
        mock.emit(.typingChanged(conversationID: .test(1), notifications: [TypingNotification(userID: a, isActive: true)]))
        mock.emit(.typingChanged(conversationID: .test(1), notifications: [TypingNotification(userID: b, isActive: false)]))
        try await waitUntil { controller.typists(in: .test(1)).count == 2 }
        #expect(controller.typists(in: .test(1)) == [a, c])
        #expect(controller.typists(in: .test(2)).isEmpty)
    }

    @Test("an expired typist drops out of the ordered list")
    func typists_staleTypist_dropsOut() async throws {
        let a = UUID(), b = UUID()
        let mock = MockConversations()
        let clock = ManualTypingClock()
        let controller = makeController(mock, incomingTypingExpiry: .milliseconds(300), typingExpiryClock: clock.clock)
        controller.start()
        try await waitUntil { mock.streamOpened }

        mock.emit(.typingChanged(conversationID: .test(1), notifications: [TypingNotification(userID: a, isActive: true)]))
        try await waitUntil { controller.typists(in: .test(1)) == [a] }
        clock.advance(by: .milliseconds(150))
        mock.emit(.typingChanged(conversationID: .test(1), notifications: [TypingNotification(userID: b, isActive: true)]))
        try await waitUntil { controller.typists(in: .test(1)) == [a, b] }

        // `a` lapses first; `b` started later, so outlives it. One sweep removes every typist
        // that is due, so a `b` expiring alongside `a` would skip `[b]` entirely.
        clock.advance(by: .milliseconds(150))
        try await waitUntil { controller.typists(in: .test(1)) == [b] }
        clock.advance(by: .milliseconds(150))
        try await waitUntil { controller.typists(in: .test(1)).isEmpty }
        #expect(!controller.isCounterpartTyping(in: .test(1)))
    }

    @Test("a STOPPED never overtakes an in-flight earlier send")
    func typingSendsStayOrdered() async throws {
        let mock = MockConversations()
        mock.holdTyping(.started)
        let controller = makeController(mock)

        controller.draftDidChange("h", in: .test(1))
        // The gate parks the STARTED in the transport, so clearing the draft queues
        // the STOPPED behind a send that is provably still in flight.
        try await waitUntil { mock.typingCallsBegun == 1 }
        controller.draftDidChange("", in: .test(1))
        mock.releaseTyping(.started)

        try await waitUntil { mock.typingCalls.count == 2 }
        #expect(mock.typingCalls.map(\.state) == [.started, .stopped])
    }

    @Test("a rapid stop-then-restart coalesces to the latest state")
    func typingBurstCoalesces() async throws {
        let mock = MockConversations()
        mock.holdTyping(.started)
        let controller = makeController(mock)

        controller.draftDidChange("h", in: .test(1))
        try await waitUntil { mock.typingCallsBegun == 1 }
        // With the STARTED parked in the transport: clear (queues STOPPED) then type
        // again. States are absolute, so the queued STOPPED is superseded — the
        // wire only ever needs the latest state.
        controller.draftDidChange("", in: .test(1))
        controller.draftDidChange("i", in: .test(1))
        // The restart queues its STARTED from a main-actor task enqueued above; yielding
        // runs it before the release below lets the drain pick the next state up.
        await Task.yield()
        mock.releaseTyping(.started)

        try await waitUntil { mock.typingCalls.count == 2 }
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

    @Test("The Chats badge counts unread chats among the ones the list shows, groups included")
    func unreadChatListCount() async {
        let me = UUID()
        let mock = MockConversations()
        func message(_ id: UInt64) -> ConversationMessage {
            ConversationMessage(id: MessageID(value: id), senderID: nil, content: .text("x"), date: Date(timeIntervalSince1970: 0), unreadSeq: 0)
        }
        mock.feed = [
            // Unread contact DM: the Chats list doesn't show it, so the badge doesn't count it.
            Conversation(
                id: ConversationID.test(1),
                members: [ConversationMember(userID: me, displayName: "", readPointer: nil)],
                lastMessage: message(2),
                lastActivity: Date(timeIntervalSince1970: 500)
            ),
            // Unread tip DM.
            Conversation(
                id: ConversationID.test(2),
                members: [ConversationMember(userID: me, displayName: "", readPointer: MessageID(value: 1))],
                lastMessage: message(5),
                lastActivity: Date(timeIntervalSince1970: 400),
                type: .tipDm
            ),
            // Read tip DM: the read pointer covers the last message.
            Conversation(
                id: ConversationID.test(3),
                members: [ConversationMember(userID: me, displayName: "", readPointer: MessageID(value: 5))],
                lastMessage: message(5),
                lastActivity: Date(timeIntervalSince1970: 300),
                type: .tipDm
            ),
        ]
        mock.groupFeed = [
            // Unread joined group: listed, so it badges the tab like any other row.
            Conversation(
                id: ConversationID.test(4),
                members: [ConversationMember(userID: me, displayName: "", readPointer: MessageID(value: 3))],
                lastMessage: message(9),
                lastActivity: Date(timeIntervalSince1970: 200),
                type: .group
            ),
        ]
        let controller = makeController(mock, selfUserID: me)
        await controller.loadFeed()

        #expect(controller.chatListConversations.map(\.id) == [.test(2), .test(3), .test(4)])
        #expect(controller.unreadChatListCount == 2)
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

    @Test("a confirmed send persists its client id to the cache (identity survives a DB round-trip)")
    func sendPersistsClientID() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let me = UUID()
        let mock = MockConversations()
        mock.sendResult = ConversationMessage(id: MessageID(value: 7), senderID: me, content: .text("hi"), date: Date(timeIntervalSince1970: 0), unreadSeq: 0)
        let controller = makeController(mock, selfUserID: me, database: database)

        #expect(await controller.send("hi", to: ConversationID.test(1)))

        let stored = try database.getConversationMessages(conversationID: ConversationID.test(1))
        #expect(stored.map(\.id.value) == [7])
        #expect(stored.first?.clientMessageID != nil)   // the send's client id round-tripped through the DB
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

    private struct ReadPointerRejected: Error {}

    /// A DM whose self row holds `pointer`, with an inbound message at each id in `messageIDs`.
    private func readPointerFixture(pointer: UInt64?, messageIDs: [UInt64]) -> (MockConversations, ConversationController) {
        let me = UUID()
        let mock = MockConversations()
        mock.feed = [Conversation(
            id: ConversationID.test(1),
            members: [
                ConversationMember(userID: me, displayName: "", readPointer: pointer.map(MessageID.init(value:))),
                ConversationMember(userID: UUID(), displayName: "Alice"),
            ],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0)
        )]
        mock.messages = messageIDs.map {
            ConversationMessage(id: MessageID(value: $0), senderID: nil, content: .text("x"), date: Date(timeIntervalSince1970: 0), unreadSeq: $0)
        }
        return (mock, makeController(mock, selfUserID: me))
    }

    private func selfPointer(_ controller: ConversationController) -> MessageID? {
        controller.conversations.first?.selfReadPointer(for: controller.selfUserID)
    }

    @Test("Advancing moves the local pointer before the RPC goes out")
    func advanceIsLocalFirst() async throws {
        let (mock, controller) = readPointerFixture(pointer: 3, messageIDs: [4, 5])
        await controller.loadFeed()
        await controller.loadMessages(for: ConversationID.test(1))

        controller.advanceReadPointer(to: MessageID(value: 5), in: ConversationID.test(1))

        #expect(selfPointer(controller) == MessageID(value: 5))
        #expect(mock.markedRead.isEmpty)
        try await waitUntil { mock.markedRead == [MessageID(value: 5)] }
        try await waitUntil { controller.store.unsyncedSelfReadPointers.isEmpty }
    }

    @Test("An advance in a chat the feed hasn't delivered still sends, and only once")
    func advanceBeforeFeedStillSends() async throws {
        let (mock, controller) = readPointerFixture(pointer: 3, messageIDs: [4, 5])
        await controller.loadMessages(for: ConversationID.test(1))

        controller.advanceReadPointer(to: MessageID(value: 5), in: ConversationID.test(1))
        controller.advanceReadPointer(to: MessageID(value: 5), in: ConversationID.test(1))

        try await waitUntil { controller.readPointerSyncTasks.isEmpty }
        #expect(mock.markedRead == [MessageID(value: 5)])
        #expect(controller.store.unsyncedSelfReadPointers.isEmpty)
    }

    @Test("An advance at or below the pointer sends nothing")
    func advanceBelowPointerIsSkipped() async throws {
        let (mock, controller) = readPointerFixture(pointer: 5, messageIDs: [4, 5])
        await controller.loadFeed()
        await controller.loadMessages(for: ConversationID.test(1))

        controller.advanceReadPointer(to: MessageID(value: 4), in: ConversationID.test(1))
        controller.advanceReadPointer(to: MessageID(value: 5), in: ConversationID.test(1))

        #expect(controller.readPointerSyncTasks.isEmpty)
        #expect(mock.markedRead.isEmpty)
        #expect(selfPointer(controller) == MessageID(value: 5))
    }

    @Test("A burst of advances sends the newest id once")
    func burstSendsNewestOnce() async throws {
        let (mock, controller) = readPointerFixture(pointer: 1, messageIDs: [2, 3, 4])
        await controller.loadFeed()
        await controller.loadMessages(for: ConversationID.test(1))

        for id in [2, 3, 4] as [UInt64] {
            controller.advanceReadPointer(to: MessageID(value: id), in: ConversationID.test(1))
        }

        try await waitUntil { controller.readPointerSyncTasks.isEmpty }
        #expect(mock.markedRead == [MessageID(value: 4)])
    }

    @Test("A failed RPC keeps the local pointer ahead, and the next feed load sends it again")
    func failedAdvanceIsResentOnFeedLoad() async throws {
        let (mock, controller) = readPointerFixture(pointer: 3, messageIDs: [4, 5])
        await controller.loadFeed()
        await controller.loadMessages(for: ConversationID.test(1))
        mock.markReadError = ReadPointerRejected()

        controller.advanceReadPointer(to: MessageID(value: 5), in: ConversationID.test(1))
        try await waitUntil { mock.markedRead.count == 1 && controller.readPointerSyncTasks.isEmpty }
        #expect(controller.store.unsyncedSelfReadPointers[ConversationID.test(1)] == MessageID(value: 5))

        // The feed still reports the server's pointer at 3.
        mock.markReadError = nil
        await controller.loadFeed()

        #expect(selfPointer(controller) == MessageID(value: 5))
        try await waitUntil { mock.markedRead == [MessageID(value: 5), MessageID(value: 5)] }
        try await waitUntil { controller.store.unsyncedSelfReadPointers.isEmpty }
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
        mock.emit(.sent([message], in: ConversationID.test(1)))

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
        mock.emit(.sent([message], in: ConversationID.test(2)))

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

    @Test("foreground with no open chat still backfills a lagging conversation via the feed's GetDelta path (missed-push-while-backgrounded regression)")
    func foregroundWithNoOpenChatBackfillsLaggingConversation() async throws {
        let mock = MockConversations()
        mock.feed = [Conversation(id: ConversationID.test(1), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 100))]
        mock.messages = [ConversationMessage(id: MessageID(value: 1), senderID: nil, content: .text("one"), date: Date(timeIntervalSince1970: 10), unreadSeq: 1, eventSequence: 1)]
        let controller = makeController(mock)

        controller.start()
        try await waitUntil { !controller.conversations.isEmpty }
        // start()'s own feed load already backfilled this (then-empty) transcript as a newest page.
        // Forget that call so the assertions below isolate the foreground hook's own fetch.
        try await waitUntil { !mock.latestPageQueries.isEmpty }
        mock.clearLatestPageQueries()
        // The classic report: nothing is on screen when the app resumes.
        controller.visibleConversationID = nil

        // The server moved past the client's cursor while backgrounded — e.g. a push the extension
        // preloaded into the shared store but couldn't advance the catch-up cursor for.
        mock.feed = [Conversation(id: ConversationID.test(1), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 200), latestEventSequence: 2)]
        mock.deltaHead = 2
        mock.deltaBatches = [MockConversations.DeltaBatch(
            messages: [ConversationMessage(id: MessageID(value: 2), senderID: nil, content: .text("missed while backgrounded"), date: Date(timeIntervalSince1970: 20), unreadSeq: 2, eventSequence: 2)],
            checkpoint: 2
        )]

        controller.handleForeground()

        try await waitUntil { controller.messages(for: ConversationID.test(1)).map(\.id.value) == [1, 2] }
        // No chat was open, so this can only have come from the feed's own backfill, not catchUpOpenChat.
        #expect(mock.deltaAfterSequences == [1])
        controller.stop()
    }

    @Test("foreground re-fetches via GetDelta even when the extension already persisted the message to the shared store")
    func foregroundRefetchesViaGetDeltaEvenWhenExtensionAlreadyPersistedMessage() async throws {
        let (database, _) = try Database.makeTemp()
        let mock = MockConversations()
        mock.feed = [Conversation(id: ConversationID.test(1), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 100))]
        mock.messages = [ConversationMessage(id: MessageID(value: 1), senderID: nil, content: .text("one"), date: Date(timeIntervalSince1970: 10), unreadSeq: 1, eventSequence: 1)]
        let controller = makeController(mock, database: database)

        controller.start()
        try await waitUntil { !controller.conversations.isEmpty }
        try await waitUntil { !mock.latestPageQueries.isEmpty }
        controller.visibleConversationID = nil
        // Prime the transcript's cached window at revision 0, the way the running app would have it
        // before backgrounding.
        #expect(controller.messages(for: ConversationID.test(1)).map(\.id.value) == [1])

        // While suspended, the notification extension wrote the pushed message straight into the
        // shared SQLite store with `cursor: 0` (deliberately not advancing the catch-up cursor - see
        // `NotificationService.persist`), bypassing the controller's `store`/`messageRevision` entirely.
        let preloaded = ConversationMessage(id: MessageID(value: 2), senderID: nil, content: .text("missed while backgrounded"), date: Date(timeIntervalSince1970: 20), unreadSeq: 2, eventSequence: 2)
        try database.persistMessages([preloaded], cursor: 0, conversationID: .test(1))

        // On foreground, because the cursor never advanced, the client's own GetDelta will report the
        // same window the extension already preloaded - scripted here to mirror that.
        mock.feed = [Conversation(id: ConversationID.test(1), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 200), latestEventSequence: 2)]
        mock.deltaHead = 2
        mock.deltaBatches = [MockConversations.DeltaBatch(messages: [preloaded], checkpoint: 2)]

        controller.handleForeground()

        // The ordinary catch-up path re-applies and re-persists the row, which bumps `messageRevision`
        // and makes the transcript visible - the same route a message never preloaded would take.
        try await waitUntil { controller.messages(for: ConversationID.test(1)).map(\.id.value) == [1, 2] }
        controller.stop()
    }

    @Test("foreground surfaces an extension-preloaded message even when the network is down (offline-resume regression)")
    func foregroundSurfacesExtensionPreloadedMessageOffline() async throws {
        let (database, _) = try Database.makeTemp()
        let mock = MockConversations()
        mock.feed = [Conversation(id: ConversationID.test(1), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 100))]
        mock.messages = [ConversationMessage(id: MessageID(value: 1), senderID: nil, content: .text("one"), date: Date(timeIntervalSince1970: 10), unreadSeq: 1, eventSequence: 1)]
        let controller = makeController(mock, database: database)

        controller.start()
        try await waitUntil { !controller.conversations.isEmpty }
        try await waitUntil { !mock.latestPageQueries.isEmpty }
        controller.visibleConversationID = nil
        // Prime the transcript's cached window, the way the running app would have it before backgrounding.
        #expect(controller.messages(for: ConversationID.test(1)).map(\.id.value) == [1])
        let cursorBeforeOffline = try database.catchupCursor(conversationID: .test(1))

        // While suspended, the notification extension wrote the pushed message straight into the
        // shared SQLite store with `cursor: 0` (deliberately not advancing the catch-up cursor - see
        // `NotificationService.persist`).
        let preloaded = ConversationMessage(id: MessageID(value: 2), senderID: nil, content: .text("missed while backgrounded, offline"), date: Date(timeIntervalSince1970: 20), unreadSeq: 2, eventSequence: 2)
        try database.persistMessages([preloaded], cursor: 0, conversationID: .test(1))

        // The server says there's something newer (so the foreground path attempts to fetch it), but
        // every network call the fetch could make fails outright - there is no connectivity at all.
        mock.feed = [Conversation(id: ConversationID.test(1), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 200), latestEventSequence: 2)]
        mock.deltaError = URLError(.notConnectedToInternet)

        controller.handleForeground()

        // The message the extension already wrote to disk must surface even though the network call
        // that would otherwise re-fetch it failed outright.
        try await waitUntil { controller.messages(for: ConversationID.test(1)).map(\.id.value) == [1, 2] }
        // No GetDelta ever landed, so the persisted catch-up cursor must be untouched - never advanced
        // from a row the extension (not the client's own catch-up) wrote.
        #expect(try database.catchupCursor(conversationID: .test(1)) == cursorBeforeOffline)
        controller.stop()
    }

    @Test("RESET_REQUIRED discards the cursor and re-syncs history via GetMessages")
    func catchUpResetResyncsHistory() async throws {
        let mock = MockConversations()
        mock.feed = [Conversation(id: ConversationID.test(1), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 100))]
        let controller = makeController(mock)

        controller.start()
        try await waitUntil { mock.connectionStateStreamOpened }
        // Catch-up requires a materialized conversation; wait for start()'s feed load to land.
        try await waitUntil { !controller.conversations.isEmpty }
        controller.visibleConversationID = ConversationID.test(1)

        // start()'s feed load backfilled the (then-empty) transcript already; this test is about the
        // page the reset path fetches, so wait that one out and forget it.
        try await waitUntil { !mock.latestPageQueries.isEmpty }
        mock.clearLatestPageQueries()

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

    @Test("a reconnect backfills a chat it surfaces, without a catch-up it has no cursor for")
    func reconnectBackfillsSurfacedConversation() async throws {
        let mock = MockConversations()
        let controller = makeController(mock)

        controller.start()
        try await waitUntil { mock.connectionStateStreamOpened }
        mock.emitConnectionState(.live)   // initial connection — baseline

        // A conversation the client has never held anything for appears on the refreshed feed. Its
        // transcript is fetched even though nothing is on screen — that is the backfill — but as a
        // newest page, since a zero cursor is nothing GetDelta could resume from.
        mock.feed = [Conversation(id: ConversationID.test(1), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 100))]
        mock.emitConnectionState(.disconnected)
        mock.emitConnectionState(.live)   // reconnect → refetch

        try await waitUntil { mock.latestPageQueries == [ConversationID.test(1)] }
        #expect(controller.conversations.map(\.id) == [ConversationID.test(1)])
        #expect(mock.deltaAfterSequences.isEmpty)
        controller.stop()
    }

    // MARK: - Backfill -

    @Test("a feed load fetches the transcript of a conversation the client holds nothing for")
    func loadFeedBackfillsEmptyConversation() async {
        let mock = MockConversations()
        mock.feed = [Conversation(id: ConversationID.test(1), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 100))]
        mock.messages = [ConversationMessage(id: MessageID(value: 9), senderID: nil, content: .text("hi"), date: Date(timeIntervalSince1970: 90), unreadSeq: 9, eventSequence: 9)]
        let controller = makeController(mock)

        await controller.loadFeed()

        #expect(mock.latestPageQueries == [ConversationID.test(1)])
        #expect(controller.messages(for: ConversationID.test(1)).map(\.id.value) == [9])
    }

    @Test("a chat holding only the feed's last-message preview still has its transcript fetched")
    func loadFeedBackfillsConversationWithOnlyAPreviewRow() async {
        let mock = MockConversations()
        // The feed persists this preview as a message row before the backfill plans, so a check for
        // "holds any message" would call this transcript cached and never fetch it — which is every
        // conversation on a fresh login.
        let preview = ConversationMessage(id: MessageID(value: 4), senderID: nil, content: .text("preview"), date: Date(timeIntervalSince1970: 40), unreadSeq: 4, eventSequence: 4)
        mock.feed = [Conversation(id: ConversationID.test(1), members: [], lastMessage: preview, lastActivity: Date(timeIntervalSince1970: 100))]
        mock.messages = [
            ConversationMessage(id: MessageID(value: 3), senderID: nil, content: .text("older"), date: Date(timeIntervalSince1970: 30), unreadSeq: 3, eventSequence: 3),
            preview,
        ]
        let controller = makeController(mock)

        await controller.loadFeed()

        #expect(mock.latestPageQueries == [ConversationID.test(1)])
        #expect(controller.messages(for: ConversationID.test(1)).map(\.id.value) == [3, 4])
    }

    @Test("a feed reporting a deleted newest message previews the message before it, not a blank row")
    func feedLoadFallsBackPastATombstone() async throws {
        let mock = MockConversations()
        let visible = ConversationMessage(id: MessageID(value: 9), senderID: nil, content: .text("hi"), date: Date(timeIntervalSince1970: 90), unreadSeq: 9, eventSequence: 9)
        mock.feed = [Conversation(id: ConversationID.test(1), members: [], lastMessage: visible, lastActivity: Date(timeIntervalSince1970: 100))]
        mock.messages = [visible]
        let controller = makeController(mock)
        await controller.loadFeed()

        // The counterpart's newest message is deleted while the chat is closed, so the client never
        // sees the event — the delete reaches it only as feed metadata, whose `lastMessage` is the
        // tombstone. Seating that verbatim leaves the row blank until the transcript is opened.
        let tombstone = ConversationMessage(
            id: MessageID(value: 10), senderID: nil,
            content: .deleted(.init(deletedBy: nil, deletedAt: Date(timeIntervalSince1970: 100))),
            date: Date(timeIntervalSince1970: 100), unreadSeq: 10, eventSequence: 10
        )
        mock.feed = [Conversation(id: ConversationID.test(1), members: [], lastMessage: tombstone, lastActivity: Date(timeIntervalSince1970: 100))]
        await controller.loadFeed()

        let conversation = try #require(controller.conversation(withID: .test(1)))
        #expect(conversation.lastMessage?.id.value == 9)
        #expect(controller.lastMessagePreview(for: conversation) { _ in nil } == "hi")
    }

    @Test("a second feed load leaves an already-cached transcript alone")
    func loadFeedSkipsCachedConversation() async {
        let mock = MockConversations()
        mock.feed = [Conversation(id: ConversationID.test(1), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 100))]
        mock.messages = [ConversationMessage(id: MessageID(value: 9), senderID: nil, content: .text("hi"), date: Date(timeIntervalSince1970: 90), unreadSeq: 9, eventSequence: 9)]
        let controller = makeController(mock)

        await controller.loadFeed()
        await controller.loadFeed()

        #expect(mock.latestPageQueries == [ConversationID.test(1)])
    }

    @Test("a feed load streams the missed window when the local cursor lags the server's head")
    func loadFeedBackfillsLaggingConversationViaDelta() async {
        let mock = MockConversations()
        mock.feed = [Conversation(id: ConversationID.test(1), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 100))]
        mock.messages = [ConversationMessage(id: MessageID(value: 2), senderID: nil, content: .text("old"), date: Date(timeIntervalSince1970: 20), unreadSeq: 2, eventSequence: 2)]
        let controller = makeController(mock)

        // Seed the cache: the newest page lands and seats the cursor at 2.
        await controller.loadFeed()

        // The server has moved past that cursor. The lag is streamed forward from where the cursor
        // sits — not re-pulled as a newest page, which would spend a GetDelta(after: 0)'s worth of
        // history and prepend it.
        mock.feed = [Conversation(id: ConversationID.test(1), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 200), latestEventSequence: 5)]
        mock.deltaHead = 5
        mock.deltaBatches = [MockConversations.DeltaBatch(
            messages: [ConversationMessage(id: MessageID(value: 3), senderID: nil, content: .text("new"), date: Date(timeIntervalSince1970: 30), unreadSeq: 3, eventSequence: 5)],
            checkpoint: 5
        )]

        await controller.loadFeed()

        #expect(mock.deltaAfterSequences == [2])
        #expect(mock.latestPageQueries == [ConversationID.test(1)]) // no second newest-page fetch
        #expect(controller.messages(for: ConversationID.test(1)).map(\.id.value) == [2, 3])
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

    @Test("a non-empty cache resolves the feed on hydration")
    func hydrate_cachedConversation_resolvesFeed() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        try database.upsertConversation(
            Conversation(id: ConversationID.test(1), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 100))
        )
        let controller = makeController(MockConversations(), database: database)
        #expect(!controller.hasResolvedFeed)

        await controller.hydrateFromDatabase()

        #expect(controller.hasResolvedFeed)
    }

    @Test("an empty cache leaves the feed unresolved until the server answers")
    func hydrate_emptyCache_waitsForFeed() async {
        let controller = makeController(MockConversations())

        await controller.hydrateFromDatabase()
        #expect(!controller.hasResolvedFeed)

        await controller.loadFeed()
        #expect(controller.hasResolvedFeed)
    }

    @Test("hydrateIfReady does nothing before a cache read has finished")
    func hydrateIfReady_noRead_isNoOp() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        try database.upsertConversation(
            Conversation(id: ConversationID.test(1), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 100))
        )
        let controller = makeController(MockConversations(), database: database)

        controller.hydrateIfReady()

        #expect(controller.conversations.isEmpty)
        #expect(!controller.hasResolvedFeed)
    }

    @Test("hydrateIfReady does not lay an applied cache back over the server's feed")
    func hydrateIfReady_afterFeed_keepsServerFeed() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        try database.upsertConversation(
            Conversation(id: ConversationID.test(1), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 100))
        )
        let mock = MockConversations()
        mock.feed = [Conversation(id: ConversationID.test(2), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 200))]
        let controller = makeController(mock, database: database)
        await controller.hydrateFromDatabase()
        await controller.loadFeed()

        controller.hydrateIfReady()

        #expect(controller.conversations.map(\.id) == [ConversationID.test(2)])
    }

    @Test("loadFeed, loadMessages, and a read advance persist — a fresh controller rehydrates the same state")
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
        controller.advanceReadPointer(to: MessageID(value: 2), in: ConversationID.test(1))

        let freshDatabase = try Database(url: url)
        let rehydrated = makeController(MockConversations(), selfUserID: selfUserID, database: freshDatabase)
        await rehydrated.hydrateFromDatabase()

        #expect(rehydrated.conversations.map(\.id) == [ConversationID.test(1)])
        #expect(rehydrated.messages(for: ConversationID.test(1)).map(\.id.value) == [1, 2])
        let pointer = rehydrated.conversations.first?.selfReadPointer(for: selfUserID)
        #expect(pointer == MessageID(value: 2))
    }

    // MARK: - Last-message preview -

    private func member(_ userID: UserID, named name: String) -> ConversationMember {
        ConversationMember(userID: userID, displayName: name)
    }

    private func textConversation(
        _ text: String,
        from sender: UserID?,
        type: ConversationType = .contactDm,
        members: [ConversationMember] = []
    ) -> Conversation {
        Conversation(
            id: ConversationID.test(1),
            members: members,
            lastMessage: ConversationMessage(
                id: MessageID(value: 1),
                senderID: sender,
                content: .text(text),
                date: Date(timeIntervalSince1970: 1),
                unreadSeq: 1
            ),
            lastActivity: Date(timeIntervalSince1970: 1),
            type: type
        )
    }

    private func cashConversation(
        mint: PublicKey,
        from sender: UserID?,
        action: CashAction = .sent,
        type: ConversationType = .contactDm,
        members: [ConversationMember] = []
    ) -> Conversation {
        Conversation(
            id: ConversationID.test(1),
            members: members,
            lastMessage: ConversationMessage(
                id: MessageID(value: 1),
                senderID: sender,
                content: .cash(ExchangedFiat(
                    onChainAmount: TokenAmount(quarks: 1_000_000, mint: mint),
                    nativeAmount: FiatAmount(value: 1, currency: .usd),
                    currencyRate: Rate(fx: 1, currency: .usd)
                )),
                cashAction: action,
                date: Date(timeIntervalSince1970: 1),
                unreadSeq: 1
            ),
            lastActivity: Date(timeIntervalSince1970: 1),
            type: type
        )
    }

    @Test("a reserve cash preview drops the currency name, which the amount already says")
    func cashPreviewOmitsReserveName() {
        let controller = makeController(MockConversations())
        let preview = controller.lastMessagePreview(for: cashConversation(mint: .usdf, from: nil)) { _ in "Dollars" }
        #expect(preview == "You received $1.00")
    }

    @Test("a community-currency cash preview names the currency")
    func cashPreviewNamesCommunityCurrency() {
        let controller = makeController(MockConversations())
        let preview = controller.lastMessagePreview(for: cashConversation(mint: .jeffy, from: nil)) { _ in "Jeffy" }
        #expect(preview == "You received $1.00 of Jeffy")
    }

    @Test("the viewer's own message is prefixed with You, in a DM as in a group")
    func textPreviewPrefixesSelf() {
        let me = UUID()
        let controller = makeController(MockConversations(), selfUserID: me)

        #expect(controller.lastMessagePreview(for: textConversation("gm", from: me)) { _ in nil } == "You: gm")
        #expect(
            controller.lastMessagePreview(
                for: textConversation("gm", from: me, type: .group, members: [member(me, named: "Me")])
            ) { _ in nil } == "You: gm"
        )
    }

    @Test("a DM is not prefixed with the counterpart's name, which the row is already titled after")
    func textPreviewLeavesDMUnprefixed() {
        let them = UUID()
        let controller = makeController(MockConversations())
        let conversation = textConversation("gm", from: them, members: [member(them, named: "Alice")])

        #expect(controller.lastMessagePreview(for: conversation) { _ in nil } == "gm")
    }

    @Test("another member's message in a group is prefixed with their name")
    func textPreviewPrefixesGroupSender() {
        let them = UUID()
        let controller = makeController(MockConversations())
        let conversation = textConversation("gm", from: them, type: .group, members: [member(them, named: "Alice")])

        #expect(controller.lastMessagePreview(for: conversation) { _ in nil } == "Alice: gm")
    }

    @Test("a group message from someone the roster subset omits goes unattributed")
    func textPreviewLeavesUnknownGroupSenderUnprefixed() {
        let controller = makeController(MockConversations())
        let conversation = textConversation("gm", from: UUID(), type: .group, members: [])

        #expect(controller.lastMessagePreview(for: conversation) { _ in nil } == "gm")
    }

    @Test("an empty body has nothing to preview, rather than a bare prefix")
    func textPreviewSkipsEmptyBody() {
        let me = UUID()
        let controller = makeController(MockConversations(), selfUserID: me)

        #expect(controller.lastMessagePreview(for: textConversation("", from: me)) { _ in nil } == nil)
    }

    @Test("the viewer's own cash reads as sent or tipped, not as a You prefix")
    func cashPreviewNamesSelfAction() {
        let me = UUID()
        let controller = makeController(MockConversations(), selfUserID: me)

        #expect(
            controller.lastMessagePreview(for: cashConversation(mint: .usdf, from: me)) { _ in nil }
                == "You sent $1.00"
        )
        #expect(
            controller.lastMessagePreview(for: cashConversation(mint: .usdf, from: me, action: .tipped)) { _ in nil }
                == "You tipped $1.00"
        )
    }

    @Test("a group member's cash is attributed to them, with the tip verb they used")
    func cashPreviewAttributesGroupSender() {
        let them = UUID()
        let controller = makeController(MockConversations())
        let members = [member(them, named: "Alice")]

        #expect(
            controller.lastMessagePreview(
                for: cashConversation(mint: .jeffy, from: them, type: .group, members: members)
            ) { _ in "Jeffy" } == "Alice sent $1.00 of Jeffy"
        )
        #expect(
            controller.lastMessagePreview(
                for: cashConversation(mint: .jeffy, from: them, action: .tipped, type: .group, members: members)
            ) { _ in "Jeffy" } == "Alice tipped $1.00 of Jeffy"
        )
    }

    @Test("cash in a group is never reported as received by the viewer, who may have got none of it")
    func cashPreviewDoesNotClaimGroupCash() {
        let controller = makeController(MockConversations())
        let conversation = cashConversation(mint: .jeffy, from: UUID(), type: .group, members: [])

        #expect(controller.lastMessagePreview(for: conversation) { _ in "Jeffy" } == "$1.00 of Jeffy")
    }

    // MARK: - DB-backed transcript (no in-memory hold) -

    @Test("streamed messages persist to the DB and are read as a bounded window, not held in memory")
    func streamedMessagesAreDBBackedAndWindowed() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let mock = MockConversations()
        let controller = makeController(mock, database: database)
        controller.start()
        try await waitUntil { mock.streamOpened }

        let backlog = (1...150).map {
            ConversationMessage(id: MessageID(value: UInt64($0)), senderID: nil, content: .text("m\($0)"), date: Date(timeIntervalSince1970: TimeInterval($0)), unreadSeq: UInt64($0))
        }
        mock.emit(.sent(backlog, in: ConversationID.test(1)))

        // The whole backlog lands in the DB (nothing dropped), but the accessor reads a bounded window.
        try await waitUntil { ((try? database.messageCount(conversationID: ConversationID.test(1))) ?? 0) == 150 }
        #expect(try database.messageCount(conversationID: ConversationID.test(1)) == 150)   // full history persisted
        let window = controller.messages(for: ConversationID.test(1))
        #expect(window.count == 100)              // read as a bounded window, not the whole 150
        #expect(window.last?.id.value == 150)     // newest at the tail
        controller.stop()
    }
}
