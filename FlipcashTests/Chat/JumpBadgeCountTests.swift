//
//  JumpBadgeCountTests.swift
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
@Suite("Jump badge count")
struct JumpBadgeCountTests {

    private let id = ConversationID.test(1)

    private func message(_ id: UInt64, fromSelf: Bool) -> ConversationMessage {
        UnreadFixtures.message(id, fromSelf: fromSelf)
    }

    private func badge(for controller: ConversationController) -> JumpBadgeCount {
        JumpBadgeCount(controller: controller, conversationID: id, boundary: controller.unreadBoundary(for: id))
    }

    /// Three unread inbound messages (2...4) behind a pointer at 1.
    private func openedWithDivider(database: Database) async throws -> ConversationController {
        try await UnreadFixtures.hydratedController(
            messages: (1...4).map { message($0, fromSelf: false) },
            pointer: 1, database: database
        )
    }

    @Test("opens at the divider's count even when some unread rows are already on screen")
    func opening_equalsDividerCount() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let controller = try await openedWithDivider(database: database)
        let badge = badge(for: controller)
        #expect(badge.count == 3)

        // The opening report marks the rows on screen read; the display holds.
        controller.advanceReadPointer(to: MessageID(value: 3), in: id)

        #expect(controller.unreadBelowCount(in: id) == 1)
        #expect(badge.count == 3)
    }

    @Test("after the first user scroll the count follows the live rule")
    func afterUserScroll_followsLiveCount() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let controller = try await openedWithDivider(database: database)
        let badge = badge(for: controller)
        controller.advanceReadPointer(to: MessageID(value: 3), in: id)
        #expect(badge.count == 3)

        badge.userDidScroll()

        #expect(badge.count == 1)
        controller.advanceReadPointer(to: MessageID(value: 4), in: id)
        #expect(badge.count == 0)
    }

    @Test("a chat with no divider opens at zero")
    func noDivider_isZero() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let controller = try await UnreadFixtures.hydratedController(
            messages: (1...3).map { message($0, fromSelf: false) },
            pointer: 3, database: database
        )

        #expect(badge(for: controller).count == 0)
    }

    @Test("an inbound arrival while frozen adds one to the divider's count")
    func arrivalWhileFrozen_addsToDividerCount() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let controller = try await openedWithDivider(database: database)
        let badge = badge(for: controller)
        let fired = Fired()
        let before = withObservationTracking {
            badge.count
        } onChange: {
            fired.set()
        }
        #expect(before == 3)

        controller.persist(operation: "upsert-messages") {
            try database.upsertConversationMessages([message(5, fromSelf: false)], conversationID: id)
        }

        #expect(fired.value)
        #expect(badge.count == 4)
    }

    @Test("the user's own message arriving while frozen does not count")
    func ownArrivalWhileFrozen_doesNotCount() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let controller = try await openedWithDivider(database: database)
        let badge = badge(for: controller)

        controller.persist(operation: "upsert-messages") {
            try database.upsertConversationMessages([message(5, fromSelf: true)], conversationID: id)
        }

        #expect(badge.count == 3)
    }
}
