//
//  ChatListLaunchSyncTests.swift
//  FlipcashTests
//

import Testing
import Foundation
import Observation
import FlipcashCore
import FlipcashStore
@testable import Flipcash

@MainActor
@Suite("Chat list launch sync")
struct ChatListLaunchSyncTests {

    private let me = UUID()

    private func makeController(
        _ mock: MockConversations,
        database: Database? = nil,
        timing: FeedReconcileTiming = .launch
    ) -> ConversationController {
        ConversationController(
            fetching: mock, membership: mock, viewerSettings: mock, messaging: mock, streaming: mock,
            contactNaming: MockDMContactNaming(),
            database: database ?? (try! Database.makeTemp().database),
            owner: .generate()!, selfUserID: me,
            reconcileTiming: timing
        )
    }

    private func message(_ id: UInt64, seq: UInt64? = nil, at: TimeInterval = 0) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id), senderID: nil, content: .text("m\(id)"),
            date: Date(timeIntervalSince1970: at), unreadSeq: seq ?? id, eventSequence: seq ?? id
        )
    }

    private func tipDm(
        _ n: UInt8, activity: TimeInterval, last: ConversationMessage? = nil, readPointer: UInt64? = nil
    ) -> Conversation {
        Conversation(
            id: .test(n),
            members: [ConversationMember(userID: me, displayName: "", readPointer: readPointer.map(MessageID.init(value:)))],
            lastMessage: last, lastActivity: Date(timeIntervalSince1970: activity), type: .tipDm
        )
    }

    private func group(_ n: UInt8, activity: TimeInterval) -> Conversation {
        Conversation(id: .test(n), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: activity), type: .group)
    }

    private func cached(_ rows: [Conversation]) throws -> Database {
        let db = try Database.makeTemp().database
        try db.replaceConversationFeed(rows, type: .tipDm)
        return db
    }

    private func ids(_ controller: ConversationController) -> [ConversationID] {
        controller.chatListConversations.map(\.id)
    }

    // MARK: - One reconcile

    @Test("three feeds land as one update with unread counts already populated")
    func feedsApplyAsOneUpdate() async throws {
        let unread = tipDm(2, activity: 200, last: message(5), readPointer: 1)
        let db = try cached([tipDm(1, activity: 100), tipDm(2, activity: 50, last: message(5), readPointer: 1)])
        let mock = MockConversations()
        mock.feed = [tipDm(1, activity: 100), unread]
        mock.groupFeed = [group(9, activity: 300)]
        mock.feedDelay = .milliseconds(150)
        mock.singleMessages = [MessageID(value: 1): message(1, seq: 3)]
        let controller = makeController(mock, database: db)

        let observer = ListObserver(controller, unreadFor: unread)
        controller.start()
        try await waitUntil { ids(controller) == [.test(1), .test(2)] }
        observer.start()

        await controller.loadFeed()
        try await Task.sleep(for: .milliseconds(50))

        #expect(ids(controller) == [.test(9), .test(2), .test(1)])
        let first = try #require(observer.shown.first)
        #expect(first.ids == [.test(9), .test(2), .test(1)])
        #expect(first.unread != nil)
        #expect(observer.shown.allSatisfy { $0.ids == first.ids && $0.unread == first.unread })
        controller.stop()
    }

    @Test("a slow feed is capped: the others apply, and the slow one applies when it lands", .timingSensitive)
    func slowFeedIsCapped() async throws {
        let db = try cached([tipDm(1, activity: 100)])
        let mock = MockConversations()
        mock.feed = [tipDm(1, activity: 100), tipDm(2, activity: 200)]
        mock.groupFeed = [group(9, activity: 300)]
        mock.groupFeedDelay = .milliseconds(800)
        let controller = makeController(mock, database: db, timing: .init(feedCap: .milliseconds(100), unreadCap: .milliseconds(100)))
        controller.start()

        try await waitUntil { ids(controller) == [.test(2), .test(1)] }
        #expect(mock.groupFeedCalls == 1)
        try await waitUntil { ids(controller) == [.test(9), .test(2), .test(1)] }
        controller.stop()
    }

    @Test("slow unread lookups don't hold the list past their cap", .timingSensitive)
    func unreadIsCapped() async throws {
        let unread = tipDm(2, activity: 200, last: message(5), readPointer: 1)
        let db = try cached([tipDm(1, activity: 100)])
        let mock = MockConversations()
        mock.feed = [tipDm(1, activity: 100), unread]
        mock.singleMessages = [MessageID(value: 1): message(1, seq: 3)]
        mock.singleMessageDelay = .milliseconds(800)
        let controller = makeController(mock, database: db, timing: .init(feedCap: .seconds(2), unreadCap: .milliseconds(100)))
        controller.start()

        try await waitUntil { ids(controller) == [.test(2), .test(1)] }
        #expect(controller.unreadCount(for: unread) == nil)
        try await waitUntil { controller.unreadCount(for: unread) != nil }
        controller.stop()
    }

    @Test("the reconcile does not wait on backfill")
    func reconcileDoesNotWaitOnBackfill() async throws {
        let db = try cached([tipDm(1, activity: 100)])
        let mock = MockConversations()
        mock.feed = [tipDm(1, activity: 100), tipDm(2, activity: 200)]
        mock.messagesDelay = .seconds(30)
        let controller = makeController(mock, database: db)
        controller.start()

        try await waitUntil { ids(controller) == [.test(2), .test(1)] }
        try await waitUntil { !mock.latestPageQueries.isEmpty }
        controller.stop()
    }

    @Test("the cached list is ready before any feed answers")
    func cacheIsInstant() async throws {
        let db = try cached([tipDm(1, activity: 100)])
        let mock = MockConversations()
        mock.feed = [tipDm(1, activity: 100), tipDm(2, activity: 200)]
        mock.feedDelay = .seconds(30)
        let controller = makeController(mock, database: db)
        controller.start()

        try await waitUntil { ids(controller) == [.test(1)] && mock.dmFeedCalls > 0 }
        controller.stop()
    }

    // MARK: - Idempotence

    @Test("backfill and a feed with older data leave rows, previews and order alone")
    func olderDataDoesNotMutate() async throws {
        let db = try cached([
            tipDm(1, activity: 200, last: message(5, at: 200)),
            tipDm(2, activity: 100, last: message(4, at: 100)),
        ])
        let mock = MockConversations()
        // A feed behind what is stored, and a transcript page behind it too.
        mock.feed = [
            tipDm(1, activity: 150, last: message(3, at: 150)),
            tipDm(2, activity: 100, last: message(4, at: 100)),
        ]
        mock.messages = [message(2, at: 50)]
        let controller = makeController(mock, database: db)
        controller.start()
        try await waitUntil { ids(controller) == [.test(1), .test(2)] }

        await controller.loadFeed()

        let rows = controller.chatListConversations
        #expect(rows.map(\.id) == [.test(1), .test(2)])
        #expect(rows.map(\.lastActivity) == [Date(timeIntervalSince1970: 200), Date(timeIntervalSince1970: 100)])
        #expect(rows.compactMap(\.lastMessage?.id.value) == [5, 4])
        controller.stop()
    }

    @Test("a live event older than the stored activity does not reorder the list")
    func olderStreamEventDoesNotReorder() async throws {
        let db = try cached([tipDm(1, activity: 200), tipDm(2, activity: 100)])
        let mock = MockConversations()
        mock.feed = [tipDm(1, activity: 200), tipDm(2, activity: 100)]
        let controller = makeController(mock, database: db)
        controller.start()
        try await waitUntil { mock.streamOpened && ids(controller) == [.test(1), .test(2)] }
        await controller.loadFeed()

        mock.emit(.lastActivityChanged(conversationID: .test(2), date: Date(timeIntervalSince1970: 10)))
        try await Task.sleep(for: .milliseconds(100))
        #expect(ids(controller) == [.test(1), .test(2)])

        mock.emit(.lastActivityChanged(conversationID: .test(2), date: Date(timeIntervalSince1970: 900)))
        try await waitUntil { ids(controller) == [.test(2), .test(1)] }
        controller.stop()
    }

    // MARK: - Empty store

    @Test("with nothing cached each feed shows as it lands")
    func emptyStoreIsProgressive() async throws {
        let mock = MockConversations()
        mock.feed = [tipDm(2, activity: 200)]
        mock.feedDelay = .milliseconds(500)
        mock.groupFeed = [group(9, activity: 300)]
        let controller = makeController(mock)
        controller.start()

        // The group feed answers at once and shows without waiting on the DM feeds.
        try await waitUntil { ids(controller) == [.test(9)] }
        #expect(controller.chatListConversations.count == 1)
        try await waitUntil { ids(controller) == [.test(9), .test(2)] }
        controller.stop()
    }

    // MARK: - Dedupe

    @Test("start and a foreground refresh make one fetch per feed")
    func dedupesFeedLoads() async throws {
        let db = try cached([tipDm(1, activity: 100)])
        let mock = MockConversations()
        mock.feed = [tipDm(1, activity: 100)]
        mock.feedDelay = .milliseconds(200)
        let controller = makeController(mock, database: db)
        controller.start()
        try await waitUntil { mock.dmFeedCalls > 0 }
        await controller.loadFeed()
        // contactDm + tipDm + groups, once each.
        #expect(mock.dmFeedCalls == 2)
        #expect(mock.groupFeedCalls == 1)
        controller.stop()
    }
}

/// Records what the Chats list shows each time it changes, read after the change has fully applied.
@MainActor
private final class ListObserver {
    struct Shown { let ids: [ConversationID]; let unread: Int? }

    private(set) var shown: [Shown] = []
    private let controller: ConversationController
    private let conversation: Conversation

    init(_ controller: ConversationController, unreadFor conversation: Conversation) {
        self.controller = controller
        self.conversation = conversation
    }

    func start() {
        withObservationTracking {
            _ = controller.chatListConversations
            _ = controller.unreadCount(for: conversation)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.shown.append(Shown(ids: self.controller.chatListConversations.map(\.id), unread: self.controller.unreadCount(for: self.conversation)))
                self.start()
            }
        }
    }
}

@MainActor
@Suite("BoundedWait", .timingSensitive)
struct BoundedWaitTests {

    @Test("returns when every unit has signalled, ahead of the cap")
    func returnsWhenDone() async {
        let wait = BoundedWait(expecting: 2)
        Task { wait.signal(); wait.signal() }
        let start = ContinuousClock.now
        await wait.wait(upTo: .seconds(10))
        #expect(ContinuousClock.now - start < .seconds(5))
        #expect(wait.isClosed)
    }

    @Test("returns at the cap when a unit never signals, then reports later ones as late")
    func returnsAtCap() async {
        let wait = BoundedWait(expecting: 2)
        wait.signal()
        await wait.wait(upTo: .milliseconds(50))
        #expect(wait.isClosed)
    }
}

@MainActor
@Suite("BackfillQueue")
struct BackfillQueueTests {

    @Test("enqueue skips duplicates; remove takes a chat out ahead of its turn")
    func removeAndDedupe() {
        var queue = BackfillQueue()
        queue.enqueue([.init(conversationID: .test(1), kind: .delta), .init(conversationID: .test(2), kind: .newestPage)])
        queue.enqueue([.init(conversationID: .test(1), kind: .delta)])
        #expect(queue.count == 2)
        let first = queue.remove(.test(1))
        let second = queue.remove(.test(1))
        #expect(first)
        #expect(!second)
        #expect(queue.popNext()?.conversationID == .test(2))
        #expect(queue.popNext() == nil)
    }

    @Test("workers are claimed up to the limit and topped up as they finish")
    func claimsWorkersUpToLimit() {
        var queue = BackfillQueue()
        queue.enqueue((1...6).map { .init(conversationID: .test($0), kind: .delta) })
        #expect(queue.claimWorkers(limit: 4) == 4)
        #expect(queue.claimWorkers(limit: 4) == 0)
        queue.releaseWorker()
        #expect(queue.claimWorkers(limit: 4) == 1)
    }
}
