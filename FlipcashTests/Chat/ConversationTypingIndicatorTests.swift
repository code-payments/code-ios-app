//
//  ConversationTypingIndicatorTests.swift
//  FlipcashTests
//

import Testing
import Foundation
import FlipcashCore
import FlipcashStore
@testable import Flipcash

/// The typing row the load coordinator appends: a group's carries the typists' avatars, a DM's
/// carries none.
@MainActor
@Suite("ConversationLoadCoordinator typing indicator")
struct ConversationTypingIndicatorTests {

    private func waitUntil(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        for _ in 0..<50 where !condition() {
            try? await Task.sleep(for: .milliseconds(20))
        }
        try #require(condition(), "Timed out waiting for condition after ~1s", sourceLocation: sourceLocation)
    }

    private let me = UUID()

    private func conversation(_ type: ConversationType, members: [ConversationMember]) -> Conversation {
        Conversation(
            id: .test(1),
            members: [ConversationMember(userID: me, displayName: "Me")] + members,
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 100),
            type: type,
            title: type == .group ? "Group" : nil
        )
    }

    /// A started controller whose store holds `conversation`, and a coordinator over it.
    private func make(
        _ conversation: Conversation,
        database: Database
    ) async throws -> (MockConversations, ConversationController, ConversationLoadCoordinator) {
        let mock = MockConversations()
        switch conversation.type {
        case .group:
            mock.groupFeed = [conversation]
        case .contactDm, .tipDm:
            mock.feed = [conversation]
        }
        let controller = ConversationController(
            fetching: mock, membership: mock, viewerSettings: mock, messaging: mock, streaming: mock,
            contactNaming: MockDMContactNaming(),
            database: database,
            owner: .generate()!, selfUserID: me
        )
        controller.start()
        try await waitUntil { mock.streamOpened && controller.conversation(withID: .test(1)) != nil }

        let coordinator = ConversationLoadCoordinator(
            conversationID: .test(1),
            controller: controller,
            session: .mock,
            knownAuthors: KnownAuthorDirectory(read: { [:] }, fetch: { _ in throw CancellationError() }, cache: { _, _ in }),
            profileCard: { nil }
        )
        return (mock, controller, coordinator)
    }

    private func typing(_ userID: UserID, in mock: MockConversations) {
        mock.emit(.typingChanged(conversationID: .test(1), notifications: [TypingNotification(userID: userID, isActive: true)]))
    }

    /// The typists the coordinator's typing row carries, or nil when it has no typing row.
    private func typingRow(_ coordinator: ConversationLoadCoordinator) -> [ChatAuthor]? {
        for item in coordinator.items {
            switch item {
            case .typingIndicator(let typists):
                return typists
            case .message, .dateSeparator, .unreadDivider, .profileCard, .groupCard:
                continue
            }
        }
        return nil
    }

    @Test("A group's typing row carries each typist, oldest first")
    func typingRow_group_carriesTypistsOldestFirst() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let alice = UUID(), bob = UUID()
        let group = conversation(.group, members: [
            ConversationMember(userID: alice, displayName: "Alice"),
            ConversationMember(userID: bob, displayName: "Bob"),
        ])
        let (mock, controller, coordinator) = try await make(group, database: database)

        typing(alice, in: mock)
        try await waitUntil { controller.typists(in: .test(1)).count == 1 }
        typing(bob, in: mock)
        try await waitUntil { typingRow(coordinator)?.count == 2 }

        let typists = try #require(typingRow(coordinator))
        #expect(typists.map(\.id) == [alice, bob])
        #expect(typists.map(\.name) == ["Alice", "Bob"])
        // The typists' pictures are fetched alongside the senders'.
        #expect(Set(coordinator.attributedMembers.compactMap(\.userID)) == [alice, bob])
    }

    @Test("A DM's typing row carries no avatars")
    func typingRow_dm_carriesNoAvatars() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let them = UUID()
        let dm = conversation(.contactDm, members: [ConversationMember(userID: them, displayName: "Them")])
        let (mock, _, coordinator) = try await make(dm, database: database)

        typing(them, in: mock)
        try await waitUntil { typingRow(coordinator) != nil }

        #expect(typingRow(coordinator) == [])
        #expect(coordinator.attributedMembers.isEmpty)
    }

    @Test("A group with more typists than the cap keeps the newest three")
    func typingRow_overCap_keepsNewestThree() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let typists = (0..<5).map { _ in UUID() }
        let group = conversation(.group, members: typists.enumerated().map {
            ConversationMember(userID: $0.element, displayName: "Typist \($0.offset)")
        })
        let (mock, controller, coordinator) = try await make(group, database: database)

        // One at a time, so each starts at a distinct instant and the order is the emit order.
        for (index, typist) in typists.enumerated() {
            typing(typist, in: mock)
            try await waitUntil { controller.typists(in: .test(1)).count == index + 1 }
        }
        try await waitUntil { typingRow(coordinator)?.first?.id == typists[2] }

        #expect(ChatItem.maxTypingAvatars == 3)
        #expect(typingRow(coordinator)?.map(\.id) == Array(typists.suffix(3)))
    }
}
