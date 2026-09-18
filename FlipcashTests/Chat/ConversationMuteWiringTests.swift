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

    private func makeController(_ mock: MockConversations, database: Database) -> ConversationController {
        ConversationController(
            fetching: mock, membership: mock, viewerSettings: mock, messaging: mock, streaming: mock,
            contactNaming: MockDMContactNaming(),
            database: database,
            owner: .generate()!, selfUserID: UUID()
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
}
