//
//  ConversationRosterTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import FlipcashCore

/// Roster updates and group membership: the two pieces of group state the client derives rather than
/// reads off the chat metadata. Roster updates are convergent by summary version rather than
/// sequenced, and membership is inferred from where a chat came from, so both have to hold under
/// out-of-order and repeated delivery.
@Suite("Conversation roster + group membership")
struct ConversationRosterTests {

    private func conversationID(_ byte: UInt8) -> ConversationID {
        ConversationID(data: Data(repeating: byte, count: 32))
    }

    private func userID(_ byte: UInt8) -> UserID {
        UUID(uuid: (byte, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    }

    private func member(_ byte: UInt8, name: String? = nil) -> ConversationMember {
        ConversationMember(userID: userID(byte), displayName: name ?? "member-\(byte)")
    }

    private func group(
        _ byte: UInt8,
        lastActivity: TimeInterval = 0,
        members: [ConversationMember] = [],
        memberCount: UInt64 = 0,
        version: UInt64 = 0
    ) -> Conversation {
        Conversation(
            id: conversationID(byte),
            members: members,
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: lastActivity),
            type: .group,
            rosterSummary: ConversationRosterSummary(memberCount: memberCount, version: version)
        )
    }

    private func joined(_ member: ConversationMember, memberCount: UInt64, version: UInt64) -> DecodedRosterUpdate {
        DecodedRosterUpdate(
            rosterSummary: ConversationRosterSummary(memberCount: memberCount, version: version),
            change: .joined(member: member, chat: nil)
        )
    }

    private func left(_ userID: UserID, memberCount: UInt64, version: UInt64) -> DecodedRosterUpdate {
        DecodedRosterUpdate(
            rosterSummary: ConversationRosterSummary(memberCount: memberCount, version: version),
            change: .left(userID: userID)
        )
    }

    // MARK: - Roster updates

    @Test("A join appends the member and advances the summary")
    func joinAppendsMember() {
        var store = ConversationStore()
        store.setFeed([group(1, members: [member(1)], memberCount: 1, version: 4)])

        store.applyRosterUpdates([joined(member(2), memberCount: 2, version: 5)], in: conversationID(1))

        let conversation = store.conversations[0]
        #expect(conversation.members.map(\.userID) == [userID(1), userID(2)])
        #expect(conversation.rosterSummary == ConversationRosterSummary(memberCount: 2, version: 5))
    }

    @Test("A leave removes the member and advances the summary")
    func leaveRemovesMember() {
        var store = ConversationStore()
        store.setFeed([group(1, members: [member(1), member(2)], memberCount: 2, version: 4)])

        store.applyRosterUpdates([left(userID(1), memberCount: 1, version: 5)], in: conversationID(1))

        let conversation = store.conversations[0]
        #expect(conversation.members.map(\.userID) == [userID(2)])
        #expect(conversation.rosterSummary.memberCount == 1)
    }

    @Test("Out-of-order updates apply in version order")
    func updatesApplyInVersionOrder() {
        var store = ConversationStore()
        store.setFeed([group(1, members: [member(1)], memberCount: 1, version: 4)])

        // The leave (v6) is delivered ahead of the join (v5) it depends on.
        store.applyRosterUpdates([
            left(userID(2), memberCount: 1, version: 6),
            joined(member(2), memberCount: 2, version: 5),
        ], in: conversationID(1))

        let conversation = store.conversations[0]
        #expect(conversation.members.map(\.userID) == [userID(1)])
        #expect(conversation.rosterSummary.version == 6)
    }

    @Test("An update at or below the cached version is dropped")
    func staleUpdatesAreDropped() {
        var store = ConversationStore()
        store.setFeed([group(1, members: [member(1)], memberCount: 1, version: 5)])

        store.applyRosterUpdates([
            joined(member(2), memberCount: 2, version: 5),
            joined(member(3), memberCount: 2, version: 4),
        ], in: conversationID(1))

        let conversation = store.conversations[0]
        #expect(conversation.members.map(\.userID) == [userID(1)])
        #expect(conversation.rosterSummary.version == 5)
    }

    @Test("Redelivering the same join twice leaves one member")
    func redeliveryIsIdempotent() {
        var store = ConversationStore()
        store.setFeed([group(1, members: [member(1)], memberCount: 1, version: 4)])
        let update = joined(member(2), memberCount: 2, version: 5)

        store.applyRosterUpdates([update], in: conversationID(1))
        store.applyRosterUpdates([update], in: conversationID(1))

        #expect(store.conversations[0].members.map(\.userID) == [userID(1), userID(2)])
    }

    @Test("A join for a member already on the roster replaces their record")
    func joinReplacesExistingMember() {
        var store = ConversationStore()
        store.setFeed([group(1, members: [member(2, name: "old")], memberCount: 1, version: 4)])

        store.applyRosterUpdates([joined(member(2, name: "new"), memberCount: 1, version: 5)], in: conversationID(1))

        #expect(store.conversations[0].members.map(\.displayName) == ["new"])
    }

    @Test("An unidentified joiner still advances the member count")
    func unidentifiedJoinerAdvancesCount() {
        var store = ConversationStore()
        store.setFeed([group(1, members: [member(1)], memberCount: 1, version: 4)])
        let anonymous = ConversationMember(userID: nil, displayName: "someone")

        store.applyRosterUpdates([joined(anonymous, memberCount: 2, version: 5)], in: conversationID(1))

        let conversation = store.conversations[0]
        #expect(conversation.members.map(\.userID) == [userID(1)])
        #expect(conversation.rosterSummary.memberCount == 2)
    }

    @Test("A roster update for a chat the store doesn't hold is a no-op")
    func rosterUpdateForUnknownChatIsIgnored() {
        var store = ConversationStore()
        store.setFeed([group(1, memberCount: 1, version: 4)])

        store.applyRosterUpdates([joined(member(2), memberCount: 2, version: 5)], in: conversationID(9))

        #expect(store.conversations.count == 1)
        #expect(store.conversations[0].rosterSummary.version == 4)
    }

    // MARK: - Membership

    @Test("A DM is always a member chat; an unjoined group is not")
    func dmIsAlwaysAMember() {
        var store = ConversationStore()
        let dm = Conversation(id: conversationID(1), members: [], lastMessage: nil, lastActivity: .distantPast, type: .tipDm)
        store.setFeed([dm, group(2)])

        #expect(store.isMember(of: dm))
        #expect(!store.isMember(of: group(2)))
    }

    @Test("The group feed seats membership for the groups it returns")
    func groupFeedSeatsMembership() {
        var store = ConversationStore()

        let departed = store.setGroupFeed([group(1, lastActivity: 100), group(2, lastActivity: 200)])

        #expect(departed.isEmpty)
        #expect(store.joinedGroups == [conversationID(1), conversationID(2)])
        #expect(store.conversations.map(\.id) == [conversationID(2), conversationID(1)])
    }

    @Test("A group missing from a later feed is reported departed and dropped")
    func departedGroupIsDropped() {
        var store = ConversationStore()
        store.setGroupFeed([group(1, lastActivity: 100), group(2, lastActivity: 200)])

        let departed = store.setGroupFeed([group(2, lastActivity: 200)])

        #expect(departed == [conversationID(1)])
        #expect(store.conversations.map(\.id) == [conversationID(2)])
        #expect(store.joinedGroups == [conversationID(2)])
    }

    @Test("The group feed leaves an unjoined group in the store")
    func unjoinedGroupSurvivesTheFeed() {
        var store = ConversationStore()
        // A group reached by a /chat/{id} link: in the store so its screen can offer the join, and
        // absent from a feed that only carries joined chats.
        store.apply(.metadataRefresh(group(9, lastActivity: 50)))

        let departed = store.setGroupFeed([group(1, lastActivity: 100)])

        #expect(departed.isEmpty)
        #expect(store.conversations.map(\.id).contains(conversationID(9)))
        #expect(!store.isMember(of: group(9)))
    }

    @Test("The group feed leaves the DM feeds alone")
    func groupFeedLeavesDMsAlone() {
        var store = ConversationStore()
        let dm = Conversation(id: conversationID(5), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 300), type: .tipDm)
        store.setFeed([dm])

        store.setGroupFeed([group(1, lastActivity: 100)])

        #expect(store.conversations.map(\.id) == [conversationID(5), conversationID(1)])
    }

    @Test("setMembership records a join and a leave")
    func setMembershipRecordsBothWays() {
        var store = ConversationStore()
        store.apply(.metadataRefresh(group(1)))

        store.setMembership(true, in: conversationID(1))
        #expect(store.isMember(of: group(1)))

        store.setMembership(false, in: conversationID(1))
        #expect(!store.isMember(of: group(1)))
    }

    @Test("A leave keeps the chat in the store")
    func leaveKeepsTheChat() {
        var store = ConversationStore()
        store.setGroupFeed([group(1, lastActivity: 100)])

        store.setMembership(false, in: conversationID(1))

        // The screen the user left from is still on top and needs the chat to draw its gate.
        #expect(store.conversations.map(\.id) == [conversationID(1)])
        #expect(!store.isMember(of: group(1)))
    }

    @Test("Seeded memberships survive a later group feed that repeats them")
    func seededMembershipsSurviveTheFeed() {
        var store = ConversationStore()
        store.seedMemberships([conversationID(1)])
        store.apply(.metadataRefresh(group(1)))

        #expect(store.isMember(of: group(1)))

        let departed = store.setGroupFeed([group(1, lastActivity: 100)])
        #expect(departed.isEmpty)
        #expect(store.isMember(of: group(1)))
    }

    @Test("A seeded membership the group feed doesn't repeat is a departure")
    func seededMembershipAbsentFromFeedDeparts() {
        var store = ConversationStore()
        store.seedMemberships([conversationID(1)])
        store.apply(.metadataRefresh(group(1)))

        let departed = store.setGroupFeed([])

        #expect(departed == [conversationID(1)])
        #expect(store.conversations.isEmpty)
    }

    @Test("A metadata refresh doesn't clobber membership")
    func metadataRefreshPreservesMembership() {
        var store = ConversationStore()
        store.setGroupFeed([group(1, lastActivity: 100)])

        store.apply(.metadataRefresh(group(1, lastActivity: 200, memberCount: 9, version: 3)))

        #expect(store.isMember(of: group(1)))
        #expect(store.conversations[0].rosterSummary.memberCount == 9)
    }

    @Test("A rosterChanged stream event reaches the store's roster")
    func rosterChangedEventApplies() {
        var store = ConversationStore()
        store.setFeed([group(1, members: [member(1)], memberCount: 1, version: 4)])

        store.apply(.rosterChanged(conversationID: conversationID(1), updates: [joined(member(2), memberCount: 2, version: 5)]))

        #expect(store.conversations[0].members.map(\.userID) == [userID(1), userID(2)])
    }
}
