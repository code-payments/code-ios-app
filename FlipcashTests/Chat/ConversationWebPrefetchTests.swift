//
//  ConversationWebPrefetchTests.swift
//  FlipcashTests
//

import Testing
import Foundation
import FlipcashCore
import FlipcashStore
@testable import Flipcash

/// The load coordinator prefetches web cards only for the chat on screen, in the foreground, and in
/// a group only for a member (parity decision D5).
@MainActor
@Suite("ConversationLoadCoordinator web prefetch")
struct ConversationWebPrefetchTests {

    private let me = UUID()
    private let them = UUID()

    private final class Spy {
        var batches: [[LinkCard]] = []
    }

    private func conversation(_ type: ConversationType) -> Conversation {
        Conversation(
            id: .test(1),
            members: [ConversationMember(userID: me, displayName: "Me"), ConversationMember(userID: them, displayName: "Them")],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 100),
            type: type,
            title: type == .group ? "Group" : nil
        )
    }

    private func message(_ id: UInt64, _ body: String) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id),
            senderID: them,
            content: .text(body),
            date: Date(timeIntervalSince1970: 200 + Double(id)),
            unreadSeq: id
        )
    }

    private enum Membership { case dm, memberGroup }

    /// Lands a page with two web links and one cash-free text message, then reports what was prefetched.
    private func prefetched(
        _ membership: Membership,
        visible: Bool = true,
        active: Bool = true
    ) async throws -> [[LinkCard]] {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let mock = MockConversations()
        switch membership {
        case .dm:             mock.feed = [conversation(.contactDm)]
        case .memberGroup:    mock.groupFeed = [conversation(.group)]
        }
        mock.deltaBatches = [.init(messages: [
            message(1, "see https://example.com/a"),
            message(2, "no link here"),
            message(3, "and https://example.org/b#frag"),
        ], checkpoint: 3)]
        mock.deltaHead = 3

        let controller = ConversationController(
            fetching: mock, membership: mock, viewerSettings: mock, messaging: mock, streaming: mock,
            contactNaming: MockDMContactNaming(),
            database: database,
            owner: .generate()!, selfUserID: me
        )
        controller.start()
        try await waitUntil { mock.streamOpened }
        switch membership {
        case .dm:
            try await waitUntil { controller.conversation(withID: .test(1)) != nil }
        case .memberGroup:
            await controller.loadGroupFeed()
        }
        if visible { controller.visibleConversationID = .test(1) }

        let spy = Spy()
        let coordinator = ConversationLoadCoordinator(
            conversationID: .test(1),
            controller: controller,
            session: .mock,
            knownAuthors: KnownAuthorDirectory(read: { [:] }, fetch: { _ in throw CancellationError() }, cache: { _, _ in }),
            prefetchWebCards: { spy.batches.append($0) },
            isAppActive: { active }
        )

        await controller.catchUp(conversationID: .test(1))
        // The prefetch decision runs on the same main-actor turn that lands the mapped items.
        try await waitUntil { coordinator.items.count >= 3 }
        controller.stop()
        return spy.batches
    }

    @Test("A visible, active DM prefetches each web card in the page")
    func visibleActiveDM_prefetchesWebCards() async throws {
        let batches = try await prefetched(.dm)
        let urls = try #require(batches.last).compactMap { card -> String? in
            guard case .web(let web) = card else { return nil }
            return web.url.absoluteString
        }
        #expect(urls == ["https://example.com/a", "https://example.org/b#frag"])
    }

    @Test("A visible, active member of a group prefetches")
    func memberGroup_prefetches() async throws {
        #expect(try await !prefetched(.memberGroup).isEmpty)
    }

    // A non-member reads a transcript only when they satisfy a gated group's rule, which needs a
    // balance this harness does not model, so the member rule is checked on the decision itself.
    @Test("A non-member reading a group does not prefetch, even on screen and in the foreground")
    func nonMember_doesNotPrefetch() {
        #expect(!ConversationLoadCoordinator.mayPrefetchWebCards(isMember: false, isVisible: true, isAppActive: true))
        #expect(ConversationLoadCoordinator.mayPrefetchWebCards(isMember: true, isVisible: true, isAppActive: true))
    }

    @Test("A chat that is not on screen does not prefetch")
    func notVisible_doesNotPrefetch() async throws {
        #expect(try await prefetched(.dm, visible: false).isEmpty)
    }

    @Test("A visible chat while the app is inactive does not prefetch")
    func inactive_doesNotPrefetch() async throws {
        #expect(try await prefetched(.dm, active: false).isEmpty)
    }
}
