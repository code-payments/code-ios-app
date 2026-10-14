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

        controller.advanceReadPointer(to: MessageID(value: 2), in: id)

        #expect(controller.unreadBelowCount(in: id) == 2)
    }

    @Test("an inbound message with a higher id increments the count")
    func inboundArrival_increments() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let controller = try await UnreadFixtures.hydratedController(
            messages: [message(1, fromSelf: false), message(2, fromSelf: false)],
            pointer: 1, database: database
        )
        #expect(controller.unreadBelowCount(in: id) == 1)

        try database.upsertConversationMessages([message(3, fromSelf: false)], conversationID: id)

        #expect(controller.unreadBelowCount(in: id) == 2)
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
