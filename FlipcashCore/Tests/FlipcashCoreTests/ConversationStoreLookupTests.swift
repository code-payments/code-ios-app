//
//  ConversationStoreLookupTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import FlipcashCore

/// Per-id lookups and writes after every mutation that inserts, removes or reorders feed rows. Each
/// test moves rows, then writes a preview by id and reads it back with a linear scan, so a write
/// that landed on the wrong row fails here.
@Suite("ConversationStore lookup by id")
struct ConversationStoreLookupTests {

    private func conversationID(_ byte: UInt8) -> ConversationID {
        ConversationID(data: Data(repeating: byte, count: 32))
    }

    private func conversation(_ byte: UInt8, lastActivity: TimeInterval, type: ConversationType = .contactDm) -> Conversation {
        Conversation(
            id: conversationID(byte),
            members: [],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: lastActivity),
            type: type
        )
    }

    private func message(_ id: UInt64) -> ConversationMessage {
        ConversationMessage(id: MessageID(value: id), senderID: nil, content: .text("m\(id)"), date: Date(timeIntervalSince1970: 0), unreadSeq: 0, eventSequence: 0)
    }

    /// Writes a distinct preview to every held row by id, then checks each one landed on its own row
    /// and that `conversation(withID:)` and `contains(_:)` agree with a scan.
    private func expectLookupsMatchScan(_ store: inout ConversationStore, previewBase: UInt64, sourceLocation: SourceLocation = #_sourceLocation) {
        let ids = store.conversations.map(\.id)
        for (offset, id) in ids.enumerated() {
            store.setFeedPreview(message(previewBase + UInt64(offset)), in: id)
        }
        for (offset, id) in ids.enumerated() {
            let scanned = store.conversations.first { $0.id == id }
            #expect(scanned?.lastMessage?.id.value == previewBase + UInt64(offset), sourceLocation: sourceLocation)
            #expect(store.conversation(withID: id)?.id == id, sourceLocation: sourceLocation)
            #expect(store.contains(id), sourceLocation: sourceLocation)
        }
    }

    @Test("Lookups follow a feed replace")
    func afterSetFeed() {
        var store = ConversationStore()
        store.setFeed([conversation(1, lastActivity: 10), conversation(2, lastActivity: 20)])
        store.setFeed([conversation(3, lastActivity: 30), conversation(1, lastActivity: 5), conversation(4, lastActivity: 40)])

        #expect(store.conversations.map(\.id) == [conversationID(4), conversationID(3), conversationID(1)])
        #expect(!store.contains(conversationID(2)))
        #expect(store.conversation(withID: conversationID(2)) == nil)
        expectLookupsMatchScan(&store, previewBase: 100)
    }

    @Test("Lookups follow a type-scoped feed replace")
    func afterSetFeedOfType() {
        var store = ConversationStore()
        store.setFeed([conversation(1, lastActivity: 10), conversation(2, lastActivity: 20, type: .group)])
        store.setFeed([conversation(3, lastActivity: 30), conversation(4, lastActivity: 5)], type: .contactDm)

        #expect(!store.contains(conversationID(1)))
        #expect(store.contains(conversationID(2)))
        expectLookupsMatchScan(&store, previewBase: 100)
    }

    @Test("Lookups follow an insert from a metadata refresh, which re-sorts")
    func afterInsert() {
        var store = ConversationStore()
        store.setFeed([conversation(1, lastActivity: 10), conversation(2, lastActivity: 20)])
        store.apply(.metadataRefresh(conversation(3, lastActivity: 15)))

        #expect(store.conversations.map(\.id) == [conversationID(2), conversationID(3), conversationID(1)])
        expectLookupsMatchScan(&store, previewBase: 100)
    }

    @Test("Lookups follow a remove from the middle")
    func afterRemove() {
        var store = ConversationStore()
        store.setFeed([conversation(1, lastActivity: 30), conversation(2, lastActivity: 20), conversation(3, lastActivity: 10)])
        store.remove(conversationID(2))

        #expect(!store.contains(conversationID(2)))
        #expect(store.conversation(withID: conversationID(2)) == nil)
        store.setFeedPreview(message(1), in: conversationID(2))
        #expect(store.conversations.allSatisfy { $0.lastMessage == nil })
        expectLookupsMatchScan(&store, previewBase: 100)
    }

    @Test("Lookups follow a reorder when activity moves the last row to the top")
    func afterReorder() {
        var store = ConversationStore()
        store.setFeed([conversation(1, lastActivity: 30), conversation(2, lastActivity: 20), conversation(3, lastActivity: 10)])
        store.advanceLastActivity(to: Date(timeIntervalSince1970: 99), in: conversationID(3))

        #expect(store.conversations.map(\.id) == [conversationID(3), conversationID(1), conversationID(2)])
        store.setFeedPreview(message(7), in: conversationID(3))
        #expect(store.conversations.first?.lastMessage?.id.value == 7)
        expectLookupsMatchScan(&store, previewBase: 100)
    }

    @Test("Lookups follow a group feed that drops a departed group")
    func afterGroupFeedDrop() {
        var store = ConversationStore()
        store.setGroupFeed([conversation(1, lastActivity: 30, type: .group), conversation(2, lastActivity: 20, type: .group)])
        store.setFeed([conversation(3, lastActivity: 10)], type: .contactDm)
        let departed = store.setGroupFeed([conversation(2, lastActivity: 20, type: .group)])

        #expect(departed == [conversationID(1)])
        #expect(!store.contains(conversationID(1)))
        #expect(store.conversations.map(\.id) == [conversationID(2), conversationID(3)])
        expectLookupsMatchScan(&store, previewBase: 100)
    }

    @Test("An empty group feed drops every joined group")
    func afterEmptyGroupFeed() {
        var store = ConversationStore()
        store.setFeed([conversation(3, lastActivity: 10)], type: .contactDm)
        store.setGroupFeed([conversation(1, lastActivity: 30, type: .group)])
        store.setGroupFeed([])

        #expect(store.conversations.map(\.id) == [conversationID(3)])
        expectLookupsMatchScan(&store, previewBase: 100)
    }

    @Test("Lookups hold across a long run of mixed mutations")
    func afterMixedMutations() {
        var store = ConversationStore()
        store.setFeed((1...40).map { conversation(UInt8($0), lastActivity: TimeInterval($0)) })
        for step in 1...40 {
            let byte = UInt8((step * 7) % 40 + 1)
            switch step % 4 {
            case 0: store.remove(conversationID(byte))
            case 1: store.advanceLastActivity(to: Date(timeIntervalSince1970: TimeInterval(1000 + step)), in: conversationID(byte))
            case 2: store.apply(.metadataRefresh(conversation(UInt8(100 + step), lastActivity: TimeInterval(step * 3))))
            default: store.setHidden(true, in: conversationID(byte))
            }
            for held in store.conversations {
                #expect(store.conversation(withID: held.id)?.id == held.id)
            }
        }
        expectLookupsMatchScan(&store, previewBase: 1000)
    }
}
