//
//  ConversationStoreReadPointerTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import FlipcashCore

@Suite("ConversationStore self READ pointer")
struct ConversationStoreReadPointerTests {

    private let me = UUID()
    private let them = UUID()

    private func conversationID(_ byte: UInt8) -> ConversationID {
        ConversationID(data: Data(repeating: byte, count: 32))
    }

    private func conversation(_ byte: UInt8, pointer: UInt64?, type: ConversationType = .contactDm) -> Conversation {
        Conversation(
            id: conversationID(byte),
            members: [
                ConversationMember(userID: me, displayName: "", readPointer: pointer.map(MessageID.init(value:))),
                ConversationMember(userID: them, displayName: "Them"),
            ],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0),
            type: type
        )
    }

    private func pointer(_ store: ConversationStore, _ byte: UInt8) -> MessageID? {
        store.selfReadPointer(for: conversationID(byte), selfUserID: me)
    }

    @Test("A local advance is recorded as unsynced until the server takes it")
    func localAdvanceIsUnsynced() {
        var store = ConversationStore(selfUserID: me)
        store.setFeed([conversation(1, pointer: 3)])

        store.advanceSelfReadPointer(to: MessageID(value: 5), in: conversationID(1), selfUserID: me)
        #expect(pointer(store, 1) == MessageID(value: 5))
        #expect(store.unsyncedSelfReadPointers[conversationID(1)] == MessageID(value: 5))

        store.didSyncSelfReadPointer(MessageID(value: 5), in: conversationID(1))
        #expect(store.unsyncedSelfReadPointers.isEmpty)
    }

    @Test("An older sync doesn't clear a later local advance")
    func olderSyncKeepsLaterAdvance() {
        var store = ConversationStore(selfUserID: me)
        store.setFeed([conversation(1, pointer: 3)])
        store.advanceSelfReadPointer(to: MessageID(value: 5), in: conversationID(1), selfUserID: me)
        store.advanceSelfReadPointer(to: MessageID(value: 7), in: conversationID(1), selfUserID: me)

        store.didSyncSelfReadPointer(MessageID(value: 5), in: conversationID(1))
        #expect(store.unsyncedSelfReadPointers[conversationID(1)] == MessageID(value: 7))
    }

    @Test("A feed load with an older server pointer keeps the local one, and marks it unsynced")
    func feedLoadNeverLowersSelfPointer() {
        var store = ConversationStore(selfUserID: me)
        store.setFeed([conversation(1, pointer: 3)])
        store.advanceSelfReadPointer(to: MessageID(value: 5), in: conversationID(1), selfUserID: me)
        store.didSyncSelfReadPointer(MessageID(value: 5), in: conversationID(1))

        store.setFeed([conversation(1, pointer: 3)], type: .contactDm)

        #expect(pointer(store, 1) == MessageID(value: 5))
        #expect(store.unsyncedSelfReadPointers[conversationID(1)] == MessageID(value: 5))
    }

    @Test("A server pointer that catches up clears the unsynced entry")
    func serverCatchingUpClearsUnsynced() {
        var store = ConversationStore(selfUserID: me)
        store.setFeed([conversation(1, pointer: 3)])
        store.advanceSelfReadPointer(to: MessageID(value: 5), in: conversationID(1), selfUserID: me)

        store.setFeed([conversation(1, pointer: 6)], type: .contactDm)

        #expect(pointer(store, 1) == MessageID(value: 6))
        #expect(store.unsyncedSelfReadPointers.isEmpty)
    }

    @Test("A metadata refresh never lowers the self pointer")
    func metadataRefreshNeverLowersSelfPointer() {
        var store = ConversationStore(selfUserID: me)
        store.setFeed([conversation(1, pointer: 3)])
        store.advanceSelfReadPointer(to: MessageID(value: 5), in: conversationID(1), selfUserID: me)

        store.apply(.metadataRefresh(conversation(1, pointer: nil)))

        #expect(pointer(store, 1) == MessageID(value: 5))
        #expect(store.unsyncedSelfReadPointers[conversationID(1)] == MessageID(value: 5))
    }

    @Test("A streamed self pointer at or past the local one clears the unsynced entry")
    func streamedSelfPointerClearsUnsynced() {
        var store = ConversationStore(selfUserID: me)
        store.setFeed([conversation(1, pointer: 3)])
        store.advanceSelfReadPointer(to: MessageID(value: 5), in: conversationID(1), selfUserID: me)

        store.apply(.readPointersChanged(conversationID: conversationID(1), pointers: [MemberReadPointer(userID: them, value: MessageID(value: 9))]))
        #expect(store.unsyncedSelfReadPointers[conversationID(1)] == MessageID(value: 5))

        store.apply(.readPointersChanged(conversationID: conversationID(1), pointers: [MemberReadPointer(userID: me, value: MessageID(value: 5))]))
        #expect(store.unsyncedSelfReadPointers.isEmpty)
    }

    @Test("Loading one feed type leaves another type's unsynced pointer alone")
    func typedFeedLoadLeavesOtherTypes() {
        var store = ConversationStore(selfUserID: me)
        store.setFeed([conversation(1, pointer: 3), conversation(2, pointer: 1, type: .tipDm)])
        store.advanceSelfReadPointer(to: MessageID(value: 5), in: conversationID(1), selfUserID: me)

        store.setFeed([conversation(2, pointer: 1, type: .tipDm)], type: .tipDm)

        #expect(store.unsyncedSelfReadPointers[conversationID(1)] == MessageID(value: 5))
        #expect(pointer(store, 1) == MessageID(value: 5))
    }
}
