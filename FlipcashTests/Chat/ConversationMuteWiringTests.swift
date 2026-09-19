//
//  ConversationMuteWiringTests.swift
//  FlipcashTests
//

import Testing
import Foundation
import FlipcashCore
import FlipcashStore
@testable import Flipcash

/// Muting through the controller: the RPC's viewer state is seated under the same version rule the
/// stream uses, cached so a cold start renders it, and dropped when the user leaves.
@MainActor
@Suite("ConversationController mute")
struct ConversationMuteWiringTests {

    private func makeController(
        _ mock: MockConversations,
        selfUserID: UserID = UUID(),
        database: Database
    ) -> ConversationController {
        ConversationController(
            fetching: mock, membership: mock, viewerSettings: mock, messaging: mock, streaming: mock,
            contactNaming: MockDMContactNaming(),
            database: database,
            owner: .generate()!, selfUserID: selfUserID
        )
    }

    private func tipDM(_ byte: UInt8, between selfUserID: UserID, and them: UserID) -> Conversation {
        Conversation(
            id: .test(byte),
            members: [
                ConversationMember(userID: selfUserID, displayName: "me"),
                ConversationMember(userID: them, displayName: "them"),
            ],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0),
            type: .tipDm
        )
    }

    private func group(_ byte: UInt8) -> Conversation {
        Conversation(
            id: .test(byte),
            members: [],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0),
            type: .group,
            title: "Group \(byte)"
        )
    }

    private let noon = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Muting seats the returned viewer state and caches it")
    func muteSeatsAndPersists() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let mock = MockConversations()
        mock.groupFeed = [group(1)]
        let controller = makeController(mock, database: database)
        await controller.loadGroupFeed()

        let expiry = noon.addingTimeInterval(3600)
        try await controller.mute(conversationID: .test(1), .until(expiry))

        #expect(mock.muted.map(\.conversationID) == [.test(1)])
        #expect(mock.muted.first?.mute == .until(expiry))
        #expect(controller.isMuted(conversationID: .test(1), at: noon))
        // And it lapses on its own, with nothing further applied.
        #expect(controller.isMuted(conversationID: .test(1), at: expiry) == false)

        let cached = try #require(try database.getConversations().first)
        #expect(cached.isMuted(at: noon))
    }

    @Test("Unmuting is its own call and clears the mute")
    func unmuteClearsTheMute() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let mock = MockConversations()
        mock.groupFeed = [group(1)]
        let controller = makeController(mock, database: database)
        await controller.loadGroupFeed()

        try await controller.mute(conversationID: .test(1), .forever)
        mock.viewerStateResult = ConversationViewerState(mute: nil, version: 2)
        try await controller.unmute(conversationID: .test(1))

        #expect(mock.unmuted == [.test(1)])
        #expect(controller.isMuted(conversationID: .test(1), at: noon) == false)
        #expect(try #require(try database.getConversations().first).isMuted(at: noon) == false)
    }

    @Test("A failed mute leaves the chat unmuted")
    func failedMuteChangesNothing() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let mock = MockConversations()
        mock.groupFeed = [group(1)]
        mock.muteError = ErrorMuteChat.denied
        let controller = makeController(mock, database: database)
        await controller.loadGroupFeed()

        await #expect(throws: ErrorMuteChat.self) {
            try await controller.mute(conversationID: .test(1), .forever)
        }
        #expect(controller.isMuted(conversationID: .test(1), at: noon) == false)
    }

    /// The server clears mute on leave and restarts the version with it, so a rejoin must not show
    /// the old mute — and must not have its first update dropped as stale.
    @Test("Leaving drops the mute, and a rejoin's first update still applies")
    func leaveClearsMute() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let mock = MockConversations()
        mock.groupFeed = [group(1)]
        let controller = makeController(mock, database: database)
        await controller.loadGroupFeed()

        mock.viewerStateResult = ConversationViewerState(mute: .forever, version: 9)
        try await controller.mute(conversationID: .test(1), .forever)
        #expect(controller.isMuted(conversationID: .test(1), at: noon))

        try await controller.leave(conversationID: .test(1))
        #expect(controller.isMuted(conversationID: .test(1), at: noon) == false)
        #expect(try #require(try database.getConversations().first).viewerState == nil)

        controller.store.applyViewerStateChanged(
            ConversationViewerState(mute: .forever, version: 1),
            in: .test(1)
        )
        #expect(controller.isMuted(conversationID: .test(1), at: noon))
    }

    // MARK: - The DM behind a counterpart's profile

    @Test("A counterpart's tip DM is the chat their profile offers to mute")
    func tipDMResolvesByCounterpart() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let me = UUID(), them = UUID()
        let mock = MockConversations()
        mock.feed = [tipDM(2, between: me, and: them)]
        let controller = makeController(mock, selfUserID: me, database: database)
        _ = await controller.loadFeed(type: .tipDm)

        #expect(controller.tipDM(withUserID: them)?.id == .test(2))

        // And it mutes like any other chat — nothing below the UI knows a DM from a group.
        try await controller.mute(conversationID: .test(2), .forever)
        #expect(controller.isMuted(conversationID: .test(2), at: noon))
    }

    @Test("Someone the user has no DM with has no chat to mute")
    func noDMResolvesToNil() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let me = UUID(), them = UUID()
        let controller = makeController(MockConversations(), selfUserID: me, database: database)

        // A tip DM doesn't exist server-side until the first tip, and the profile is reachable
        // before then — from a face in a group transcript. No chat, so no row.
        #expect(controller.tipDM(withUserID: them) == nil)
    }

    @Test("A group the two are both in is not a DM to mute")
    func sharedGroupIsNotADM() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let me = UUID(), them = UUID()
        let mock = MockConversations()
        mock.groupFeed = [
            Conversation(
                id: .test(7),
                members: [
                    ConversationMember(userID: me, displayName: "me"),
                    ConversationMember(userID: them, displayName: "them"),
                ],
                lastMessage: nil,
                lastActivity: Date(timeIntervalSince1970: 0),
                type: .group,
                title: "Group 7"
            )
        ]
        let controller = makeController(mock, selfUserID: me, database: database)
        _ = await controller.loadGroupFeed()

        // Tapping their face in this group's transcript opens their profile. Muting there must not
        // reach for the group — that mute belongs to the group's own screen.
        #expect(controller.tipDM(withUserID: them) == nil)
    }

    @Test("The viewer's own id resolves to no DM")
    func selfResolvesToNil() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let me = UUID(), them = UUID()
        let mock = MockConversations()
        mock.feed = [tipDM(2, between: me, and: them)]
        let controller = makeController(mock, selfUserID: me, database: database)
        _ = await controller.loadFeed(type: .tipDm)

        // The viewer is a member of their own DMs, so an unguarded roster match would hand back a
        // chat to mute for a profile that is the user themselves.
        #expect(controller.tipDM(withUserID: me) == nil)
    }
}
