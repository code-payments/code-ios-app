//
//  UnreadDividerTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashCore
import FlipcashStore
import FlipcashUI
@testable import Flipcash

@MainActor
@Suite("Unread divider")
struct UnreadDividerTests {

    private static let me = UUID()
    private static let them = UUID()

    /// One row of the shared-cases table in the design spec. Android encodes the same table.
    struct SharedCase: CustomTestStringConvertible, Sendable {
        let name: String
        /// (id, from self, deleted) — ids absent here were never stored.
        let messages: [(id: UInt64, fromSelf: Bool, deleted: Bool)]
        /// The viewer's READ pointer; nil stores no self member row at all.
        let pointer: UInt64?
        let dividerAbove: UInt64?
        let count: Int

        var testDescription: String { name }
    }

    nonisolated static let sharedCases: [SharedCase] = [
        SharedCase(
            name: "Plain",
            messages: [(1, false, false), (2, true, false), (3, false, false), (4, false, false)],
            pointer: 2, dividerAbove: 3, count: 2
        ),
        SharedCase(
            name: "Nothing unread",
            messages: [(1, false, false), (2, false, false)],
            pointer: 2, dividerAbove: nil, count: 0
        ),
        SharedCase(
            name: "Only own after pointer",
            messages: [(1, false, false), (2, true, false), (3, true, false)],
            pointer: 1, dividerAbove: nil, count: 0
        ),
        SharedCase(
            name: "Read-through deleted",
            messages: [(1, false, false), (3, false, false)],
            pointer: 2, dividerAbove: 3, count: 1
        ),
        SharedCase(
            name: "Unread tombstone",
            messages: [(1, false, false), (2, false, true), (3, false, false)],
            pointer: 1, dividerAbove: 2, count: 1
        ),
        SharedCase(
            name: "No self row",
            messages: [(1, false, false), (2, false, false)],
            pointer: nil, dividerAbove: nil, count: 0
        ),
        SharedCase(
            name: "Own message first after pointer",
            messages: [(1, false, false), (2, true, false), (3, false, false)],
            pointer: 1, dividerAbove: 3, count: 1
        ),
        SharedCase(
            name: "Nothing stored at or below read-through",
            messages: [(3, false, false), (4, false, false)],
            pointer: 1, dividerAbove: nil, count: 0
        ),
    ]

    private let base = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_000_000))
        .addingTimeInterval(9 * 60 * 60)

    private func message(_ id: UInt64, fromSelf: Bool, deleted: Bool = false, after offset: TimeInterval? = nil) -> ConversationMessage {
        let date = base.addingTimeInterval(offset ?? TimeInterval(id) * 60)
        return ConversationMessage(
            id: MessageID(value: id),
            senderID: fromSelf ? Self.me : Self.them,
            content: deleted ? .deleted(.init(deletedBy: Self.them, deletedAt: date)) : .text("m\(id)"),
            date: date,
            unreadSeq: id
        )
    }

    /// A controller hydrated from a database holding `messages` and, when `pointer` is non-nil, the
    /// viewer's own member row reading through it.
    private func hydratedController(
        messages: [ConversationMessage],
        pointer: UInt64?,
        database: Database
    ) async throws -> ConversationController {
        var members = [ConversationMember(userID: Self.them, displayName: "Them")]
        if let pointer {
            members.append(ConversationMember(userID: Self.me, displayName: "", readPointer: MessageID(value: pointer)))
        }
        try database.upsertConversation(
            Conversation(id: .test(1), members: members, lastMessage: nil, lastActivity: base)
        )
        try database.upsertConversationMessages(messages, conversationID: .test(1))
        let mock = MockConversations()
        let controller = ConversationController(
            fetching: mock, membership: mock, viewerSettings: mock, messaging: mock, streaming: mock,
            contactNaming: MockDMContactNaming(),
            database: database,
            owner: .generate()!, selfUserID: Self.me
        )
        await controller.hydrateFromDatabase()
        return controller
    }

    /// The id of the message row directly under the divider, or nil when there is no divider.
    private func messageUnderDivider(_ items: [ChatItem]) -> String? {
        guard let index = items.firstIndex(where: { if case .unreadDivider = $0 { true } else { false } }),
              items.indices.contains(index + 1),
              case .message(let row) = items[index + 1] else { return nil }
        return row.messageID
    }

    private func dividerCount(_ items: [ChatItem]) -> Int {
        items.filter { if case .unreadDivider = $0 { true } else { false } }.count
    }

    // MARK: - Shared cases -

    @Test("the shared cases place the divider and count as Android does", arguments: sharedCases)
    func sharedCases_placeDividerAndCount(_ shared: SharedCase) async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let messages = shared.messages.map { message($0.id, fromSelf: $0.fromSelf, deleted: $0.deleted) }
        let controller = try await hydratedController(messages: messages, pointer: shared.pointer, database: database)

        let boundary = controller.unreadBoundary(for: .test(1))
        #expect((boundary.count ?? 0) == shared.count)

        let items = ChatItem.from(
            messages,
            selfUserID: Self.me,
            deletedPresentation: .placeholder,
            unreadBoundary: boundary
        )
        #expect(messageUnderDivider(items) == shared.dividerAbove.map { "\($0)" })
        #expect(dividerCount(items) == (shared.dividerAbove == nil ? 0 : 1))
    }

    // MARK: - Resolution -

    @Test("a missing pointer resolves to none without asking for a count")
    func missingPointer_isNone() {
        var asked = false
        let boundary = UnreadBoundary.resolve(
            readPointer: nil,
            firstInbound: { _ in
                asked = true
                return MessageID(value: 2)
            },
            unreadCount: { _ in
                asked = true
                return 5
            },
            hasStored: { _ in
                asked = true
                return true
            }
        )
        #expect(boundary == .none)
        #expect(!asked)
    }

    @Test("the read-through resolves to just below the first message someone else sent after the pointer")
    func ownMessageAfterPointer_movesReadThroughPastIt() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let messages = [message(1, fromSelf: false), message(2, fromSelf: true), message(3, fromSelf: false)]
        let controller = try await hydratedController(messages: messages, pointer: 1, database: database)

        // Android's resolution gives the same value for this row, which keeps the two platforms'
        // placement identical.
        #expect(controller.unreadBoundary(for: .test(1)) == .at(readThrough: MessageID(value: 2), count: 1))
    }

    @Test("a boundary resolved before the pointer advances survives the advance")
    func resolvedBeforeAdvance_isStable() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let messages = [message(1, fromSelf: false), message(2, fromSelf: false), message(3, fromSelf: false)]
        let controller = try await hydratedController(messages: messages, pointer: 1, database: database)

        let boundary = controller.unreadBoundary(for: .test(1))
        controller.advanceReadPointer(to: MessageID(value: 3), in: .test(1))

        #expect(boundary == .at(readThrough: MessageID(value: 1), count: 2))
        #expect(controller.unreadBoundary(for: .test(1)) == .none)
    }

    // MARK: - Mapping -

    @Test("a date separator at the same gap is drawn above the divider")
    func dateSeparatorAtBoundary_drawsAboveDivider() {
        let messages = [
            message(1, fromSelf: false, after: 0),
            message(2, fromSelf: false, after: 24 * 60 * 60),
        ]
        let items = ChatItem.from(
            messages,
            selfUserID: Self.me,
            unreadBoundary: .at(readThrough: MessageID(value: 1), count: 1)
        )
        guard let divider = items.firstIndex(where: { if case .unreadDivider = $0 { true } else { false } }) else {
            Issue.record("no divider")
            return
        }
        guard case .dateSeparator = items[divider - 1] else {
            Issue.record("the row above the divider is not the date separator")
            return
        }
        #expect(messageUnderDivider(items) == "2")
    }

    @Test("the divider breaks a same-sender bubble run")
    func divider_breaksGrouping() {
        let messages = [message(1, fromSelf: false), message(2, fromSelf: false)]
        let items = ChatItem.from(
            messages,
            selfUserID: Self.me,
            unreadBoundary: .at(readThrough: MessageID(value: 1), count: 1)
        )
        let rows = items.compactMap { if case .message(let row) = $0 { row } else { nil } }
        #expect(rows.map(\.joinsBubbleBelow) == [false, false])
    }

    @Test("the label is plural, singular at one, and caps at 99+", arguments: [
        (1, "1 Unread Message"),
        (2, "2 Unread Messages"),
        (99, "99 Unread Messages"),
        (100, "99+ Unread Messages"),
    ])
    func label_formatsCount(_ count: Int, _ expected: String) {
        #expect(ChatItem.unreadDividerText(count: count) == expected)
    }
}
