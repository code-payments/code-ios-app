//
//  ConversationQuoteAuthorTests.swift
//  FlipcashTests
//

import Testing
import Foundation
import FlipcashCore
import FlipcashStore
@testable import Flipcash
@testable import FlipcashUI

/// A group reply's quote names the member who wrote the original, even when that member has no
/// other message in the rows being mapped.
@MainActor
@Suite("ConversationLoadCoordinator quote author")
struct ConversationQuoteAuthorTests {

    private let me = UUID()
    private let carol = UUID()
    private let bob = UUID()
    private let alice = UUID()

    private func text(_ id: UInt64, from sender: UUID, _ body: String, repliedTo: UInt64? = nil) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id),
            senderID: sender,
            content: .text(body),
            date: Date(timeIntervalSince1970: Double(id)),
            unreadSeq: 0,
            repliedTo: repliedTo.map { MessageID(value: $0) }
        )
    }

    /// A group where Carol is the first non-viewer member, so a quote that falls back to the
    /// counterpart reads "Carol". `persisted` is written to the store before the coordinator opens.
    private func make(
        persisted: [ConversationMessage],
        database: Database,
        type: ConversationType = .group,
        known: [UserID: ConversationMember] = [:]
    ) async throws -> (ConversationController, ConversationLoadCoordinator) {
        let group = Conversation(
            id: .test(1),
            members: [
                ConversationMember(userID: carol, displayName: "Carol"),
                ConversationMember(userID: me, displayName: "Me"),
                ConversationMember(userID: bob, displayName: "Bob"),
                ConversationMember(userID: alice, displayName: "Alice"),
            ],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 100),
            type: type,
            title: type == .group ? "Group" : nil
        )
        let mock = MockConversations()
        if type == .group { mock.groupFeed = [group] } else { mock.feed = [group] }
        let controller = ConversationController(
            fetching: mock, membership: mock, viewerSettings: mock, messaging: mock, streaming: mock,
            contactNaming: MockDMContactNaming(),
            database: database,
            owner: .generate()!, selfUserID: me
        )
        controller.start()
        try await waitUntil { mock.streamOpened && controller.conversation(withID: .test(1)) != nil }
        try database.upsertConversationMessages(persisted, conversationID: .test(1))
        let directory = KnownAuthorDirectory(read: { known }, fetch: { _ in throw CancellationError() }, cache: { _, _ in })
        await directory.reload()

        let coordinator = ConversationLoadCoordinator(
            conversationID: .test(1),
            controller: controller,
            session: .mock,
            knownAuthors: directory
        )
        return (controller, coordinator)
    }

    @Test("A pinned reply, on its own, quotes the member who wrote the original")
    func row_groupReply_namesQuotedAuthor() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let original = text(1, from: bob, "Testing")
        let reply = text(2, from: alice, "Testing pinned message", repliedTo: 1)
        let (_, coordinator) = try await make(persisted: [original, reply], database: database)

        let row = try #require(coordinator.row(for: reply))

        #expect(row.quote?.authorName == "Bob")
    }

    @Test("A pinned reply to the viewer's own message still reads You")
    func row_groupReplyToSelf_readsYou() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let original = text(1, from: me, "Testing")
        let reply = text(2, from: alice, "Testing pinned message", repliedTo: 1)
        let (_, coordinator) = try await make(persisted: [original, reply], database: database)

        let row = try #require(coordinator.row(for: reply))

        #expect(row.quote?.authorName == "You")
    }

    @Test("The transcript names a quoted author who has no other message in the window")
    func items_groupReply_namesQuotedAuthorWithoutOtherMessage() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        // Bob's message sits below the window, so only the reply is mapped.
        let original = text(1, from: bob, "Testing")
        let reply = text(200, from: alice, "Testing pinned message", repliedTo: 1)
        let filler = (2..<199).map { text(UInt64($0), from: alice, "filler \($0)") }
        let (_, coordinator) = try await make(persisted: [original] + filler + [reply], database: database)

        let rows = coordinator.items.compactMap { item -> ChatMessage? in
            if case .message(let row) = item { return row } else { return nil }
        }
        let replyRow = try #require(rows.first { $0.quote != nil })
        #expect(!rows.contains { $0.author?.id == bob })
        #expect(replyRow.quote?.authorName == "Bob")
    }

    @Test("A group sender the roster omits is named from the known authors, not the counterpart")
    func senderName_groupSenderOutsideRoster_usesKnownAuthors() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let moony = UUID()
        let (_, coordinator) = try await make(
            persisted: [],
            database: database,
            known: [moony: ConversationMember(userID: moony, displayName: "Moonyversal")]
        )

        #expect(coordinator.senderName(for: moony) == "Moonyversal")
    }

    @Test("A group sender nothing can name yet reads as nil, never as the counterpart")
    func senderName_groupUnknownSender_isNil() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let (_, coordinator) = try await make(persisted: [], database: database)

        #expect(coordinator.senderName(for: UUID()) == nil)
    }

    @Test("A DM names its other party as the counterpart")
    func senderName_dm_usesCounterpart() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let (_, coordinator) = try await make(persisted: [], database: database, type: .contactDm)

        #expect(coordinator.senderName(for: carol) == "Carol")
    }
}
