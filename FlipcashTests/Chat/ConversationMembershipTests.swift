//
//  ConversationMembershipTests.swift
//  FlipcashTests
//

import Testing
import Foundation
import FlipcashCore
import FlipcashStore
@testable import Flipcash

/// Group membership as the controller derives it: from the group feed, from an explicit join or
/// leave, and from a roster update naming the signed-in user.
@MainActor
@Suite("ConversationController group membership")
struct ConversationMembershipTests {

    private func waitUntil(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        for _ in 0..<50 where !condition() {
            try? await Task.sleep(for: .milliseconds(20))
        }
        try #require(condition(), "Timed out waiting for condition after ~1s", sourceLocation: sourceLocation)
    }

    private func makeController(
        _ mock: MockConversations,
        selfUserID: UserID = UUID(),
        database: Database
    ) -> ConversationController {
        ConversationController(
            fetching: mock, membership: mock, messaging: mock, streaming: mock,
            contactNaming: MockDMContactNaming(),
            database: database,
            owner: .generate()!, selfUserID: selfUserID
        )
    }

    private func group(
        _ byte: UInt8,
        lastActivity: TimeInterval = 0,
        members: [ConversationMember] = [],
        memberCount: UInt64 = 0,
        version: UInt64 = 0
    ) -> Conversation {
        Conversation(
            id: .test(byte),
            members: members,
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: lastActivity),
            type: .group,
            title: "Group \(byte)",
            rosterSummary: ConversationRosterSummary(memberCount: memberCount, version: version)
        )
    }

    // MARK: - Group feed

    @Test("The group feed seats membership and lists the groups")
    func groupFeedSeatsMembership() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let mock = MockConversations()
        mock.groupFeed = [group(1, lastActivity: 100), group(2, lastActivity: 200)]
        let controller = makeController(mock, database: database)

        await controller.loadGroupFeed()

        #expect(controller.joinedGroups.map(\.id) == [.test(2), .test(1)])
        #expect(try database.getGroupMemberships() == [.test(1), .test(2)])
    }

    @Test("A group missing from a later feed leaves the list and the cache")
    func departedGroupDropsOut() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let mock = MockConversations()
        mock.groupFeed = [group(1, lastActivity: 100), group(2, lastActivity: 200)]
        let controller = makeController(mock, database: database)

        await controller.loadGroupFeed()
        mock.groupFeed = [group(2, lastActivity: 200)]
        await controller.loadGroupFeed()

        #expect(controller.joinedGroups.map(\.id) == [.test(2)])
        #expect(try database.getGroupMemberships() == [.test(2)])
    }

    @Test("A group the feed doesn't carry stays in the store, unjoined")
    func linkedGroupSurvivesTheFeed() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let mock = MockConversations()
        let controller = makeController(mock, database: database)
        controller.start()
        try await waitUntil { mock.streamOpened }

        // Reached by a /chat/{id} link rather than the feed.
        mock.emit(.metadataRefresh(group(9, lastActivity: 50)))
        try await waitUntil { controller.conversation(withID: .test(9)) != nil }

        mock.groupFeed = [group(1, lastActivity: 100)]
        await controller.loadGroupFeed()

        let linked = try #require(controller.conversation(withID: .test(9)))
        #expect(!controller.isMember(of: linked))
        #expect(controller.joinedGroups.map(\.id) == [.test(1)])
    }

    // MARK: - Hydration by id

    @Test("A chat hydrated by its id records no membership, in the store or the cache")
    func hydrationByIDRecordsNoMembership() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let mock = MockConversations()
        // Reachable by `GetChat` and absent from the group feed: an invite link or a push tap into
        // a group this device has never synced.
        mock.feed = [group(9, lastActivity: 50)]
        let controller = makeController(mock, database: database)

        let hydrated = try #require(await controller.hydratedConversation(withID: .test(9)))

        // `GetChat` returns the chat, not the caller's relationship to it, so there is nothing here
        // to record. Writing the absence as a negative is the trap: it would gate a member whose
        // feed has not landed yet, and it would outlive the round trip that could correct it.
        // Membership is a positive set precisely so an unanswered question stays unanswered.
        #expect(!controller.isMember(of: hydrated))
        #expect(try database.getGroupMemberships().isEmpty)
    }

    @Test("The group feed, not the hydration, answers membership for a chat opened by id")
    func groupFeedAnswersForAHydratedChat() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let mock = MockConversations()
        mock.feed = [group(9, lastActivity: 50)]
        let controller = makeController(mock, database: database)
        _ = await controller.hydratedConversation(withID: .test(9))

        // The viewer was already in this group — joined on another device, or reinstalled. The
        // hydration could not say so; the feed can, and does, without the screen asking again.
        mock.groupFeed = [group(9, lastActivity: 50)]
        await controller.loadGroupFeed()

        let hydrated = try #require(controller.conversation(withID: .test(9)))
        #expect(controller.isMember(of: hydrated))
        #expect(try database.getGroupMemberships() == [.test(9)])
    }

    // MARK: - Join and leave

    @Test("A join seats membership, metadata, and the cache")
    func joinSeatsMembership() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let mock = MockConversations()
        mock.groupFeed = [group(1, lastActivity: 100, memberCount: 7, version: 2)]
        let controller = makeController(mock, database: database)

        try await controller.join(conversationID: .test(1))

        #expect(mock.joined == [.test(1)])
        let joined = try #require(controller.conversation(withID: .test(1)))
        #expect(controller.isMember(of: joined))
        #expect(joined.rosterSummary.memberCount == 7)
        #expect(try database.getGroupMemberships() == [.test(1)])
    }

    @Test("A refused join moves nothing")
    func refusedJoinChangesNothing() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let mock = MockConversations()
        mock.groupFeed = [group(1, lastActivity: 100)]
        mock.joinError = ErrorJoinChat.rulesNotSatisfied
        let controller = makeController(mock, database: database)

        await #expect(throws: ErrorJoinChat.rulesNotSatisfied) {
            try await controller.join(conversationID: .test(1))
        }
        #expect(controller.joinedGroups.isEmpty)
        #expect(try database.getGroupMemberships().isEmpty)
    }

    @Test("A leave drops the group from the list but keeps the chat")
    func leaveKeepsTheChat() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let mock = MockConversations()
        mock.groupFeed = [group(1, lastActivity: 100)]
        let controller = makeController(mock, database: database)
        try await controller.join(conversationID: .test(1))

        try await controller.leave(conversationID: .test(1))

        #expect(mock.left == [.test(1)])
        // The screen the user left from is still on top, so the chat has to stay readable.
        let chat = try #require(controller.conversation(withID: .test(1)))
        #expect(!controller.isMember(of: chat))
        #expect(controller.joinedGroups.isEmpty)
        #expect(try database.getGroupMemberships().isEmpty)
    }

    @Test("A refused leave keeps membership")
    func refusedLeaveKeepsMembership() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let mock = MockConversations()
        mock.groupFeed = [group(1, lastActivity: 100)]
        mock.leaveError = ErrorLeaveChat.unknown
        let controller = makeController(mock, database: database)
        try await controller.join(conversationID: .test(1))

        await #expect(throws: ErrorLeaveChat.unknown) {
            try await controller.leave(conversationID: .test(1))
        }
        #expect(controller.joinedGroups.map(\.id) == [.test(1)])
    }

    @Test("A leave the server has no record of still clears membership")
    func notFoundLeaveClearsMembership() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let mock = MockConversations()
        mock.groupFeed = [group(1, lastActivity: 100)]
        mock.leaveError = ErrorLeaveChat.notFound
        let controller = makeController(mock, database: database)
        try await controller.join(conversationID: .test(1))

        try await controller.leave(conversationID: .test(1))

        // The server holds no membership to remove, so the local flag is the stale one.
        #expect(controller.joinedGroups.isEmpty)
        #expect(try database.getGroupMemberships().isEmpty)
    }

    @Test("A DM is a member chat without ever joining")
    func dmIsAlwaysAMember() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let controller = makeController(MockConversations(), database: database)
        let dm = Conversation(id: .test(4), members: [], lastMessage: nil, lastActivity: .distantPast, type: .tipDm)

        #expect(controller.isMember(of: dm))
    }

    // MARK: - Roster updates naming the user

    @Test("A roster join naming the user seats membership and the metadata it carries")
    func rosterJoinSeatsMembership() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let me = UUID()
        let mock = MockConversations()
        let controller = makeController(mock, selfUserID: me, database: database)
        controller.start()
        try await waitUntil { mock.streamOpened }

        mock.emit(.rosterChanged(conversationID: .test(1), updates: [
            DecodedRosterUpdate(
                rosterSummary: ConversationRosterSummary(memberCount: 3, version: 1),
                change: .joined(
                    member: ConversationMember(userID: me, displayName: "me"),
                    chat: group(1, lastActivity: 100, memberCount: 3, version: 1)
                )
            )
        ]))

        try await waitUntil { controller.joinedGroups.count == 1 }
        #expect(controller.joinedGroups.map(\.id) == [.test(1)])
        #expect(try database.getGroupMemberships() == [.test(1)])
    }

    @Test("A roster leave naming the user clears membership")
    func rosterLeaveClearsMembership() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let me = UUID()
        let mock = MockConversations()
        mock.groupFeed = [group(1, lastActivity: 100, version: 1)]
        let controller = makeController(mock, selfUserID: me, database: database)
        try await controller.join(conversationID: .test(1))
        controller.start()
        try await waitUntil { mock.streamOpened }

        mock.emit(.rosterChanged(conversationID: .test(1), updates: [
            DecodedRosterUpdate(
                rosterSummary: ConversationRosterSummary(memberCount: 0, version: 2),
                change: .left(userID: me)
            )
        ]))

        try await waitUntil { controller.joinedGroups.isEmpty }
        #expect(try database.getGroupMemberships().isEmpty)
    }

    @Test("Another member's roster change leaves the user's own membership alone")
    func otherMemberRosterChangeIsIgnored() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let me = UUID(), them = UUID()
        let mock = MockConversations()
        mock.groupFeed = [group(1, lastActivity: 100, version: 1)]
        let controller = makeController(mock, selfUserID: me, database: database)
        try await controller.join(conversationID: .test(1))
        controller.start()
        try await waitUntil { mock.streamOpened }

        mock.emit(.rosterChanged(conversationID: .test(1), updates: [
            DecodedRosterUpdate(
                rosterSummary: ConversationRosterSummary(memberCount: 1, version: 2),
                change: .left(userID: them)
            )
        ]))

        try await waitUntil { controller.conversation(withID: .test(1))?.rosterSummary.version == 2 }
        #expect(controller.joinedGroups.map(\.id) == [.test(1)])
    }
}
