//
//  ConversationArchiveStateTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashAPI
@testable import FlipcashCore

/// Archive state rides on the viewer state, so it converges by version exactly as mute does: an
/// `ArchiveChat` reply, a stream event and a feed row each carry a version, and the higher one wins
/// whatever order they land in. The Android app applies the same order.
@Suite("Conversation archive state")
struct ConversationArchiveStateTests {

    private func conversationID(_ byte: UInt8) -> ConversationID {
        ConversationID(data: Data(repeating: byte, count: 32))
    }

    private func conversation(_ byte: UInt8, type: ConversationType = .group, viewerState: ConversationViewerState? = nil) -> Conversation {
        Conversation(
            id: conversationID(byte),
            members: [],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0),
            type: type,
            viewerState: viewerState
        )
    }

    private let archived = ConversationArchiveState(archivedAt: Date(timeIntervalSince1970: 1_700_000_000))

    @Test("The proto's settings.archive marks the chat archived, and its absence does not")
    func mapsFromProto() {
        let proto = Flipcash_Chat_V1_ViewerState.with {
            $0.version = 7
            $0.settings = .with { $0.archive = .with { $0.archivedAt = .init(date: Date(timeIntervalSince1970: 1_700_000_000)) } }
        }
        let state = ConversationViewerState(proto)
        #expect(state.isArchived)
        #expect(state.archive?.archivedAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(state.version == 7)

        #expect(ConversationViewerState(Flipcash_Chat_V1_ViewerState()).isArchived == false)
    }

    @Test("A stream event applies archive by version: older and equal are dropped, newer wins")
    func streamAppliesByVersion() {
        var store = ConversationStore()
        store.apply(.metadataRefresh(conversation(1, viewerState: ConversationViewerState(version: 3, archive: archived))))

        store.applyViewerStateChanged(ConversationViewerState(version: 2), in: conversationID(1))
        #expect(store.conversations[0].viewerState?.isArchived == true)

        store.applyViewerStateChanged(ConversationViewerState(version: 3), in: conversationID(1))
        #expect(store.conversations[0].viewerState?.isArchived == true)

        store.applyViewerStateChanged(ConversationViewerState(version: 4), in: conversationID(1))
        #expect(store.conversations[0].viewerState?.isArchived == false)
    }

    @Test("A DM feed row older than the held viewer state does not undo an archive")
    func dmFeedRowKeepsNewerArchive() {
        var store = ConversationStore()
        store.setFeed([conversation(1, type: .tipDm, viewerState: ConversationViewerState(version: 1))], type: .tipDm)
        store.applyViewerStateChanged(ConversationViewerState(version: 2, archive: archived), in: conversationID(1))

        store.setFeed([conversation(1, type: .tipDm, viewerState: ConversationViewerState(version: 1))], type: .tipDm)
        #expect(store.conversations[0].viewerState?.isArchived == true)
        #expect(store.conversations[0].viewerState?.version == 2)

        store.setFeed([conversation(1, type: .tipDm, viewerState: ConversationViewerState(version: 3))], type: .tipDm)
        #expect(store.conversations[0].viewerState?.isArchived == false)
    }

    @Test("A group feed row older than the held viewer state does not undo an unarchive")
    func groupFeedRowKeepsNewerUnarchive() {
        var store = ConversationStore()
        store.setGroupFeed([conversation(1, viewerState: ConversationViewerState(version: 5, archive: archived))])
        store.applyViewerStateChanged(ConversationViewerState(version: 6), in: conversationID(1))

        store.setGroupFeed([conversation(1, viewerState: ConversationViewerState(version: 5, archive: archived))])
        #expect(store.conversations[0].viewerState?.isArchived == false)
    }

    @Test("Mute and a permissions refresh carry the archive along")
    func otherViewerChangesKeepArchive() {
        var store = ConversationStore()
        store.apply(.metadataRefresh(conversation(1, viewerState: ConversationViewerState(version: 2, archive: archived))))

        store.refreshViewerPermissions(from: ConversationViewerState(version: 2, canSilence: true), in: conversationID(1))
        #expect(store.conversations[0].viewerState?.isArchived == true)

        store.apply(.metadataRefresh(conversation(1, viewerState: ConversationViewerState(version: 2, canSilence: true, archive: archived))))
        #expect(store.conversations[0].viewerState?.isArchived == true)
    }

    @Test("A viewer state stored before archive existed decodes as not archived")
    func legacyViewerStateDecodes() throws {
        let encoded = try JSONEncoder().encode(ConversationViewerState(mute: .forever, version: 4))
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "archive")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(ConversationViewerState.self, from: legacy)
        #expect(decoded.isArchived == false)
        #expect(decoded.version == 4)

        let roundTrip = try JSONDecoder().decode(ConversationViewerState.self, from: JSONEncoder().encode(ConversationViewerState(version: 1, archive: archived)))
        #expect(roundTrip.archive == archived)
    }
}
