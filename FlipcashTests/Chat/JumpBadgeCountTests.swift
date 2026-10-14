//
//  JumpBadgeCountTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import UIKit
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
        badge.openingLoadLanded()
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
        badge.openingLoadLanded()

        controller.persist(operation: "upsert-messages") {
            try database.upsertConversationMessages([message(5, fromSelf: true)], conversationID: id)
        }

        #expect(badge.count == 3)
    }

    @Test("history the opening load brings in is not an arrival")
    func openingLoadHistory_isNotAnArrival() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        // An empty cache: nothing stored when the badge is built.
        let controller = try await UnreadFixtures.hydratedController(messages: [], pointer: nil, database: database)
        let badge = badge(for: controller)

        controller.persist(operation: "load-messages") {
            try database.upsertConversationMessages((1...50).map { message($0, fromSelf: false) }, conversationID: id)
        }
        badge.openingLoadLanded()

        #expect(badge.count == 0)

        controller.persist(operation: "upsert-messages") {
            try database.upsertConversationMessages([message(51, fromSelf: false)], conversationID: id)
        }
        #expect(badge.count == 1)
    }

    @Test("the arrival cutoff uses the larger of the stored read pointer and the unsynced one")
    func arrivalCutoff_usesMaxPointer() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let controller = try await UnreadFixtures.hydratedController(
            messages: (1...4).map { message($0, fromSelf: false) },
            pointer: 5, database: database
        )
        // An unsynced advance behind the stored pointer: the stored 5 must win.
        controller.store.advanceSelfReadPointer(to: MessageID(value: 3), in: id, selfUserID: UnreadFixtures.me)
        let badge = badge(for: controller)
        badge.openingLoadLanded()

        controller.persist(operation: "upsert-messages") {
            try database.upsertConversationMessages([message(5, fromSelf: false)], conversationID: id)
        }

        // 5 is at the stored pointer, so it is not an arrival; a cutoff of 3 or 4 would count it.
        #expect(badge.count == 0)
    }

    @Test("a confirmed own text send zeroes a still-frozen badge")
    func ownSend_zeroesFrozenBadge() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let mock = MockConversations()
        mock.sendResult = message(7, fromSelf: true)
        let controller = try await UnreadFixtures.hydratedController(
            messages: (1...4).map { message($0, fromSelf: false) },
            pointer: 1, database: database, mock: mock
        )
        let badge = badge(for: controller)
        badge.openingLoadLanded()
        #expect(badge.count == 3)

        #expect(await controller.send("hi", to: id))

        #expect(badge.count == 0)
    }

    @Test("a confirmed media send zeroes a still-frozen badge")
    func mediaSend_zeroesFrozenBadge() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let controller = try await openedWithDivider(database: database)
        let badge = badge(for: controller)
        badge.openingLoadLanded()
        #expect(badge.count == 3)

        let chip = ComposerChip(image: UIImage())
        chip.uploadTask = Task { .plain(BlobID(data: Data("photo".utf8))) }
        #expect(await controller.sendMedia([chip], caption: nil, to: id))

        #expect(badge.count == 0)
    }

    @Test("a badge built after the opening load landed still excludes the loaded history")
    func builtAfterLoad_excludesHistory() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let controller = try await UnreadFixtures.hydratedController(
            messages: (1...50).map { message($0, fromSelf: false) },
            pointer: 50, database: database
        )
        let badge = JumpBadgeCount(
            controller: controller, conversationID: id,
            boundary: controller.unreadBoundary(for: id), openingLoadLanded: true
        )

        controller.persist(operation: "upsert-messages") {
            try database.upsertConversationMessages([message(51, fromSelf: false)], conversationID: id)
        }

        #expect(badge.count == 1)
    }

    @Test("an own send the viewer can't advance the pointer for leaves the badge held")
    func ownSend_withoutPointerAdvance_keepsHold() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let mock = MockConversations()
        mock.sendResult = message(9, fromSelf: true)
        // A group the viewer hasn't joined: the pointer can't move.
        let controller = try await UnreadFixtures.hydratedController(
            messages: (1...3).map { message($0, fromSelf: false) },
            pointer: nil, database: database, type: .group, mock: mock
        )
        let badge = badge(for: controller)
        badge.openingLoadLanded()
        controller.persist(operation: "upsert-messages") {
            try database.upsertConversationMessages([message(4, fromSelf: false)], conversationID: id)
        }
        #expect(badge.count == 1, "before send: \(badge.count)")

        #expect(await controller.send("hi", to: id))

        #expect(badge.isFrozen)
        #expect(controller.confirmedOwnSendCounts[id] == nil)
    }

    @Test("a failed opening load seats no cutoff; the next successful newest-page load does")
    func failedOpeningLoad_thenLaterLoad_isNotArrivals() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let mock = MockConversations()
        mock.messagesError = URLError(.notConnectedToInternet)
        let controller = try await UnreadFixtures.hydratedController(
            messages: (1...4).map { message($0, fromSelf: false) },
            pointer: 1, database: database, mock: mock
        )
        let badge = badge(for: controller)

        #expect(await controller.loadMessages(for: id) == false)
        #expect(badge.count == 3)

        // A later load by another path (a backfill, say) stores 20 more inbound; it is history.
        mock.messagesError = nil
        mock.messages = (1...24).map { message($0, fromSelf: false) }
        #expect(await controller.loadMessages(for: id))
        #expect(badge.count == 3)

        controller.persist(operation: "upsert-messages") {
            try database.upsertConversationMessages([message(25, fromSelf: false)], conversationID: id)
        }
        #expect(badge.count == 4)
    }

    @Test("a confirmed own send reports the crossed inbound messages, as Android's advance does")
    func ownSend_reportsCrossedMessages() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let spy = ReceiptSpy()
        let mock = MockConversations()
        mock.sendResult = message(7, fromSelf: true)
        let controller = try await UnreadFixtures.hydratedController(
            messages: (1...4).map { message($0, fromSelf: false) },
            pointer: 1, database: database, mock: mock,
            receipts: spy.makeReporter(selfUserID: UnreadFixtures.me)
        )

        #expect(await controller.send("hi", to: id))

        #expect(spy.messages.count == 3)
        try await waitUntil { mock.markedRead.last == MessageID(value: 7) }
    }

    @Test("a confirmed own send that doesn't move the pointer reports nothing")
    func ownSend_pointerNotMoved_reportsNothing() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let spy = ReceiptSpy()
        let mock = MockConversations()
        mock.sendResult = message(7, fromSelf: true)
        let controller = try await UnreadFixtures.hydratedController(
            messages: (1...4).map { message($0, fromSelf: false) },
            pointer: 9, database: database, mock: mock,
            receipts: spy.makeReporter(selfUserID: UnreadFixtures.me)
        )

        #expect(await controller.send("hi", to: id))

        #expect(spy.messages.isEmpty)
        #expect(spy.tips.isEmpty)
    }
}
