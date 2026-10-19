//
//  UnreadBelowCountTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashCore
import FlipcashStore
@testable import Flipcash

@MainActor
@Suite("Unread below count")
struct UnreadBelowCountTests {

    private let id = ConversationID.test(1)

    private func message(_ id: UInt64, fromSelf: Bool) -> ConversationMessage {
        UnreadFixtures.message(id, fromSelf: fromSelf)
    }

    @Test("starts equal to the unread divider's count")
    func initialCount_matchesDividerCount() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let controller = try await UnreadFixtures.hydratedController(
            messages: [message(1, fromSelf: false), message(2, fromSelf: false), message(3, fromSelf: true), message(4, fromSelf: false)],
            pointer: 1, database: database
        )

        #expect(controller.unreadBelowCount(in: id) == 2)
        #expect(controller.unreadBelowCount(in: id) == controller.unreadBoundary(for: id).count)
    }

    @Test("advancing the read pointer to a seen inbound id decrements the count")
    func advanceReadPointer_decrements() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let controller = try await UnreadFixtures.hydratedController(
            messages: (1...4).map { message($0, fromSelf: false) },
            pointer: 1, database: database
        )
        #expect(controller.unreadBelowCount(in: id) == 3)

        controller.advanceReadPointer(to: MessageID(value: 2), in: id)

        #expect(controller.unreadBelowCount(in: id) == 2)
    }

    @Test("an inbound message that lands through persist re-evaluates the count and increments it")
    func inboundArrival_increments() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let controller = try await UnreadFixtures.hydratedController(
            messages: [message(1, fromSelf: false), message(2, fromSelf: false)],
            pointer: 1, database: database
        )
        let fired = Fired()
        let before = withObservationTracking {
            controller.unreadBelowCount(in: id)
        } onChange: {
            fired.set()
        }
        #expect(before == 1)

        controller.persist(operation: "upsert-messages") {
            try database.upsertConversationMessages([message(3, fromSelf: false)], conversationID: id)
        }

        #expect(fired.value)
        #expect(controller.unreadBelowCount(in: id) == 2)
    }

    @Test("a pointer that exists only as an unsynced advance still drives the count")
    func unsyncedPointer_drivesCount() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let controller = try await UnreadFixtures.hydratedController(
            messages: (1...4).map { message($0, fromSelf: false) },
            pointer: nil, database: database, hasConversationRow: false
        )
        #expect(controller.unreadBelowCount(in: id) == 0)   // no pointer yet: nothing counts

        controller.advanceReadPointer(to: MessageID(value: 2), in: id)

        // The stored pointer is still absent; only the unsynced one reads through 2.
        #expect(controller.store.selfReadPointer(for: id, selfUserID: UnreadFixtures.me) == nil)
        #expect(controller.unreadBelowCount(in: id) == 2)
    }

    @Test("after the viewer's own send is confirmed the count is zero")
    func ownSend_clearsCount() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let mock = MockConversations()
        mock.sendResult = UnreadFixtures.message(7, fromSelf: true)
        let controller = try await UnreadFixtures.hydratedController(
            messages: (1...3).map { message($0, fromSelf: false) },
            pointer: 1, database: database, mock: mock
        )
        #expect(controller.unreadBelowCount(in: id) == 2)

        #expect(await controller.send("hi", to: id))

        #expect(controller.unreadBelowCount(in: id) == 0)
    }

    @Test("an own message does not count, and seeing the newest inbound clears the count")
    func ownSend_doesNotCount_andSeeingNewestInboundClears() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let controller = try await UnreadFixtures.hydratedController(
            messages: [message(1, fromSelf: false), message(2, fromSelf: false), message(3, fromSelf: false)],
            pointer: 1, database: database
        )
        #expect(controller.unreadBelowCount(in: id) == 2)

        try database.upsertConversationMessages([message(4, fromSelf: true)], conversationID: id)
        #expect(controller.unreadBelowCount(in: id) == 2)

        // What the landed scroll to the bottom reports: the newest inbound row now on screen.
        controller.advanceReadPointer(to: MessageID(value: 3), in: id)
        #expect(controller.unreadBelowCount(in: id) == 0)
    }

    @Test("a system message neither adds to the badge count nor becomes the newest inbound id")
    func systemMessage_doesNotChangeCountOrNewestInbound() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let controller = try await UnreadFixtures.hydratedController(
            messages: [message(1, fromSelf: false), message(2, fromSelf: false), message(3, fromSelf: false)],
            pointer: 1, database: database
        )
        #expect(controller.unreadBelowCount(in: id) == 2)

        let notice = ConversationMessage(
            id: MessageID(value: 4),
            senderID: nil,
            content: .system(fallbackText: "Alex joined", event: nil),
            date: UnreadFixtures.base.addingTimeInterval(240),
            unreadSeq: 4
        )
        try database.upsertConversationMessages([notice], conversationID: id)

        #expect(controller.unreadBelowCount(in: id) == 2)
        #expect(controller.unreadBelowCount(in: id) == controller.unreadBoundary(for: id).count)
        #expect(controller.newestInboundMessageID(in: id) == MessageID(value: 3))
    }

    @Test("an unknown read pointer counts nothing, as the divider does")
    func unknownPointer_countsNothing() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let controller = try await UnreadFixtures.hydratedController(
            messages: [message(1, fromSelf: false), message(2, fromSelf: false)],
            pointer: nil, database: database
        )

        #expect(controller.unreadBelowCount(in: id) == 0)
    }
}

/// Records that an observation-tracking `onChange` ran.
final class Fired: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool { lock.withLock { flag } }
    func set() { lock.withLock { flag = true } }
}
