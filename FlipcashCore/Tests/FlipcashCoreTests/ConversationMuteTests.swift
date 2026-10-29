//
//  ConversationMuteTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import FlipcashCore

/// Mute state: a timed mute lapses with nothing sent from the server, so the client owns the
/// comparison against now; and the state converges by version like the roster summary does.
@Suite("Conversation mute")
struct ConversationMuteTests {

    private func conversationID(_ byte: UInt8) -> ConversationID {
        ConversationID(data: Data(repeating: byte, count: 32))
    }

    private func conversation(_ byte: UInt8, viewerState: ConversationViewerState? = nil) -> Conversation {
        Conversation(
            id: conversationID(byte),
            members: [],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0),
            type: .group,
            viewerState: viewerState
        )
    }

    private let noon = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Lapse

    @Test("A mute until a future instant is active")
    func timedMuteActiveBeforeExpiry() {
        let mute = ConversationMuteState.until(noon.addingTimeInterval(60))

        #expect(mute.isActive(at: noon))
    }

    @Test("A mute lapses on its own, with nothing applied")
    func timedMuteLapses() {
        let state = ConversationViewerState(mute: .until(noon), version: 1)

        #expect(state.isMuted(at: noon.addingTimeInterval(-1)))
        // At the instant it expires, not one tick after: the comparison is strict.
        #expect(state.isMuted(at: noon) == false)
        #expect(state.isMuted(at: noon.addingTimeInterval(60)) == false)
    }

    @Test("A forever mute never lapses")
    func foreverMuteNeverLapses() {
        let state = ConversationViewerState(mute: .forever, version: 1)

        #expect(state.isMuted(at: noon))
        #expect(state.isMuted(at: .distantFuture))
    }

    @Test("A chat with no viewer state is unmuted")
    func absentViewerStateIsUnmuted() {
        #expect(conversation(1).isMuted(at: noon) == false)
        #expect(conversation(1, viewerState: ConversationViewerState(version: 3)).isMuted(at: noon) == false)
    }

    // MARK: - Convergence

    @Test("A greater version wins and a lesser one is dropped")
    func convergesByVersion() {
        var store = ConversationStore()
        store.apply(.metadataRefresh(conversation(1, viewerState: ConversationViewerState(mute: .forever, version: 2))))

        // Older: the mute stands.
        store.applyViewerStateChanged(ConversationViewerState(mute: nil, version: 1), in: conversationID(1))
        #expect(store.conversations[0].isMuted(at: noon))

        // Equal version is not greater, so it is dropped too.
        store.applyViewerStateChanged(ConversationViewerState(mute: nil, version: 2), in: conversationID(1))
        #expect(store.conversations[0].isMuted(at: noon))

        // Newer: applied.
        store.applyViewerStateChanged(ConversationViewerState(mute: nil, version: 3), in: conversationID(1))
        #expect(store.conversations[0].isMuted(at: noon) == false)
    }

    /// Mute is cleared server-side on leave, and the version restarts with it. Keeping the old
    /// version would make every post-rejoin update look stale and be dropped.
    @Test("Leaving clears the viewer state, version included")
    func clearViewerStateDropsTheVersion() {
        var store = ConversationStore()
        store.apply(.metadataRefresh(conversation(1, viewerState: ConversationViewerState(mute: .forever, version: 9))))

        store.clearViewerState(in: conversationID(1))
        #expect(store.conversations[0].viewerState == nil)
        #expect(store.conversations[0].isMuted(at: noon) == false)

        // A rejoin starts the version over; it must still be applied.
        store.applyViewerStateChanged(ConversationViewerState(mute: .forever, version: 1), in: conversationID(1))
        #expect(store.conversations[0].isMuted(at: noon))
    }

    @Test("A metadata refresh carries viewer state, so an unmute elsewhere isn't lost")
    func metadataRefreshCarriesViewerState() {
        var store = ConversationStore()
        store.apply(.metadataRefresh(conversation(1, viewerState: ConversationViewerState(mute: .forever, version: 2))))
        store.apply(.metadataRefresh(conversation(1, viewerState: ConversationViewerState(mute: nil, version: 3))))

        #expect(store.conversations[0].isMuted(at: noon) == false)
    }

    @Test("A viewer state stored before the moderation permissions decodes, keeping its mute")
    func legacyViewerStateDecodes() throws {
        let forever = try JSONEncoder().encode(ConversationViewerState(mute: .forever, canEdit: true, version: 4))
        var object = try #require(JSONSerialization.jsonObject(with: forever) as? [String: Any])
        object.removeValue(forKey: "canSilence")
        object.removeValue(forKey: "canBan")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(ConversationViewerState.self, from: legacy)

        #expect(decoded.isMuted(at: noon))
        #expect(decoded.canEdit)
        #expect(decoded.version == 4)
        #expect(decoded.canSilence == false)
        #expect(decoded.canBan == false)
    }

    @Test("Fresh permissions replace stale ones at the same version, and mute is untouched")
    func refreshViewerPermissionsIgnoresTheVersionGate() {
        var store = ConversationStore()
        store.apply(.metadataRefresh(conversation(1, viewerState: ConversationViewerState(mute: .forever, version: 2))))

        let fetched = ConversationViewerState(mute: nil, version: 2, canSilence: true, canBan: true)
        // The versioned path drops an equal version, which is why a stale row never recovered.
        store.applyViewerStateChanged(fetched, in: conversationID(1))
        #expect(store.conversations[0].viewerState?.canSilence == false)

        let changed = store.refreshViewerPermissions(from: fetched, in: conversationID(1))
        #expect(changed)
        #expect(store.conversations[0].viewerState?.canSilence == true)
        #expect(store.conversations[0].viewerState?.canBan == true)
        #expect(store.conversations[0].isMuted(at: noon))
        #expect(store.conversations[0].viewerState?.version == 2)

        let again = store.refreshViewerPermissions(from: fetched, in: conversationID(1))
        #expect(again == false)
    }

    @Test("A feed row that omits the permissions or is older does not reset the stored viewer state")
    func metadataRefreshKeepsStoredPermissions() {
        var store = ConversationStore()
        store.apply(.metadataRefresh(conversation(1, viewerState: ConversationViewerState(mute: .forever, version: 2, canSilence: true, canBan: true))))

        store.apply(.metadataRefresh(conversation(1, viewerState: ConversationViewerState(mute: .forever, version: 2))))
        #expect(store.conversations[0].viewerState?.canSilence == true)
        #expect(store.conversations[0].viewerState?.canBan == true)

        store.apply(.metadataRefresh(conversation(1, viewerState: ConversationViewerState(mute: nil, version: 1))))
        #expect(store.conversations[0].isMuted(at: noon))

        store.apply(.metadataRefresh(conversation(1, viewerState: nil)))
        #expect(store.conversations[0].viewerState?.canSilence == true)
    }
}
