//
//  GroupRostersTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Private group rosters")
struct GroupRostersTests {

    private let group = ConversationID.test(1)

    private func member(_ name: String, id: UserID = UUID(), joinedAt seconds: TimeInterval = 0, version: UInt64 = 1) -> ConversationMember {
        ConversationMember(userID: id, displayName: name, joinedAt: Date(timeIntervalSince1970: seconds), version: version)
    }

    private func event(_ changes: [(RosterChange, UInt64)]) -> ConversationStreamEvent {
        .rosterChanged(conversationID: group, updates: changes.map { change, version in
            DecodedRosterUpdate(rosterSummary: ConversationRosterSummary(memberCount: 0, version: version), change: change)
        })
    }

    @Test("Orders the creator first, then the most recently joined")
    func ordering() async {
        let host = member("Host", joinedAt: 0)
        let early = member("Early", joinedAt: 10)
        let late = member("Late", joinedAt: 20)
        let rosters = GroupRosters { _ in [early, host, late] }

        await rosters.refresh(group)

        #expect(rosters.members(for: group, creator: host.userID).map(\.displayName) == ["Host", "Late", "Early"])
    }

    @Test("A failed read keeps the roster unloaded")
    func failedRead() async {
        let rosters = GroupRosters { _ in throw ErrorGetChat.denied }

        await rosters.refresh(group)

        #expect(!rosters.isLoaded(group))
    }

    @Test("Stream changes are ignored until the roster is first read")
    func ignoresUnreadRoster() {
        let rosters = GroupRosters { _ in [] }

        rosters.apply(event([(.joined(member: member("New"), chat: nil), 2)]))

        #expect(!rosters.isLoaded(group))
    }

    @Test("A join and a leave from the stream update a read roster")
    func appliesStream() async {
        let stays = member("Stays")
        let leaves = member("Leaves")
        let rosters = GroupRosters { _ in [stays, leaves] }
        await rosters.refresh(group)

        rosters.apply(event([
            (.joined(member: member("New", version: 3), chat: nil), 3),
            (.left(userID: leaves.userID!), 4),
        ]))

        #expect(Set(rosters.members(for: group, creator: nil).map(\.displayName)) == ["Stays", "New"])
    }

    @Test("A trailing page doesn't bring back a member the stream saw leave")
    func trailingPageAfterLeave() async {
        let leaves = member("Leaves", version: 2)
        var page = [leaves]
        let rosters = GroupRosters { _ in page }
        await rosters.refresh(group)
        rosters.apply(event([(.left(userID: leaves.userID!), 5)]))

        page = [leaves]
        await rosters.refresh(group)

        #expect(rosters.members(for: group, creator: nil).isEmpty)
    }

    @Test("A page doesn't replace an entry the stream delivered at a newer version")
    func keepsNewerVersion() async {
        let id = UUID()
        var page = [member("Old", id: id, version: 1)]
        let rosters = GroupRosters { _ in page }
        await rosters.refresh(group)
        rosters.apply(event([(.joined(member: member("Rejoined", id: id, version: 6), chat: nil), 6)]))

        page = [member("Old", id: id, version: 1)]
        await rosters.refresh(group)

        #expect(rosters.members(for: group, creator: nil).map(\.displayName) == ["Rejoined"])
    }
}
