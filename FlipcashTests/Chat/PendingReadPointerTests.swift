//
//  PendingReadPointerTests.swift
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
@Suite("Pending read pointer")
struct PendingReadPointerTests {

    private let id = ConversationID.test(1)

    /// Three unread inbound messages (2...4) behind a pointer at 1.
    private func openedWithDivider(database: Database) async throws -> ConversationController {
        try await UnreadFixtures.hydratedController(
            messages: (1...4).map { UnreadFixtures.message($0, fromSelf: false) },
            pointer: 1, database: database
        )
    }

    @Test("seen rows leave the controller's pointer alone until committed")
    func markSeen_holdsPointerUntilCommit() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let controller = try await openedWithDivider(database: database)
        let pending = PendingReadPointer(controller: controller, conversationID: id, delay: .seconds(60))

        pending.markSeen(MessageID(value: 3))

        #expect(pending.seenThrough == MessageID(value: 3))
        #expect(controller.readThrough(for: id) == MessageID(value: 1))

        pending.commit()

        #expect(controller.readThrough(for: id) == MessageID(value: 3))
    }

    @Test("an older report doesn't move the seen id back")
    func markSeen_neverRegresses() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let controller = try await openedWithDivider(database: database)
        let pending = PendingReadPointer(controller: controller, conversationID: id, delay: .seconds(60))

        pending.markSeen(MessageID(value: 4))
        pending.markSeen(MessageID(value: 2))

        #expect(pending.seenThrough == MessageID(value: 4))
    }

    @Test("commits by itself once reports stop for the delay")
    func markSeen_commitsAfterDelay() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let controller = try await openedWithDivider(database: database)
        let pending = PendingReadPointer(controller: controller, conversationID: id, delay: .milliseconds(10))

        pending.markSeen(MessageID(value: 4))

        try await waitUntil { controller.readThrough(for: id) == MessageID(value: 4) }
    }

    @Test("the live badge counts from the uncommitted seen id")
    func badge_countsFromSeenThrough() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let controller = try await openedWithDivider(database: database)
        let pending = PendingReadPointer(controller: controller, conversationID: id, delay: .seconds(60))
        let badge = JumpBadgeCount(
            controller: controller,
            conversationID: id,
            boundary: controller.unreadBoundary(for: id),
            pendingRead: pending
        )
        badge.userDidScroll()
        #expect(badge.count == 3)

        pending.markSeen(MessageID(value: 3))

        #expect(badge.count == 1)
        #expect(controller.readThrough(for: id) == MessageID(value: 1))
    }

    @Test("an unknown pointer still counts nothing, whatever was seen")
    func badge_unknownPointer_isZero() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let controller = try await UnreadFixtures.hydratedController(
            messages: (1...4).map { UnreadFixtures.message($0, fromSelf: false) },
            pointer: nil, database: database
        )
        let pending = PendingReadPointer(controller: controller, conversationID: id, delay: .seconds(60))
        let badge = JumpBadgeCount(
            controller: controller,
            conversationID: id,
            boundary: controller.unreadBoundary(for: id),
            pendingRead: pending
        )
        badge.userDidScroll()

        pending.markSeen(MessageID(value: 2))

        #expect(badge.count == 0)
    }
}
