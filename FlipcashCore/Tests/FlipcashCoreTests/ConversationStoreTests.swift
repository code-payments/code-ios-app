//
//  ConversationStoreTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import FlipcashCore

@Suite("ConversationStore reconciliation")
struct ConversationStoreTests {

    private func conversationID(_ byte: UInt8) -> ConversationID {
        ConversationID(data: Data(repeating: byte, count: 32))
    }

    private func conversation(_ byte: UInt8, lastActivity: TimeInterval) -> Conversation {
        Conversation(
            id: conversationID(byte),
            members: [],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: lastActivity)
        )
    }

    private func message(_ id: UInt64, _ text: String = "hi", at: TimeInterval = 0, eventSequence: UInt64 = 0) -> ConversationMessage {
        ConversationMessage(id: MessageID(value: id), senderID: nil, content: .text(text), date: Date(timeIntervalSince1970: at), unreadSeq: 0, eventSequence: eventSequence)
    }

    private func deleted(_ id: UInt64, at: TimeInterval = 0, eventSequence: UInt64) -> ConversationMessage {
        ConversationMessage(id: MessageID(value: id), senderID: nil, content: .deleted, date: Date(timeIntervalSince1970: at), unreadSeq: 0, eventSequence: eventSequence)
    }

    @Test("setFeed sorts by last activity, most recent first")
    func feedSortsByActivity() {
        var store = ConversationStore()
        store.setFeed([
            conversation(1, lastActivity: 100),
            conversation(2, lastActivity: 300),
            conversation(3, lastActivity: 200),
        ])
        #expect(store.conversations.map(\.id) == [conversationID(2), conversationID(3), conversationID(1)])
    }

    @Test("mergeMessages dedupes by id and keeps oldest first; a higher event_sequence wins")
    func messagesMergeGapless() {
        var store = ConversationStore()
        store.mergeMessages([message(3, eventSequence: 3), message(1, eventSequence: 1)], into: conversationID(1))
        store.mergeMessages([message(1, "updated", eventSequence: 2), message(2, eventSequence: 2)], into: conversationID(1))

        let messages = store.messages(for: conversationID(1))
        #expect(messages.map(\.id.value) == [1, 2, 3])
        #expect(messages.first?.content == .text("updated")) // higher event_sequence wins
    }

    @Test("mergeMessages dedupes a re-delivered message without duplicating the row")
    func messagesDedupeEcho() {
        var store = ConversationStore()
        store.mergeMessages([message(1, eventSequence: 1), message(2, "hi", eventSequence: 2)], into: conversationID(1))
        store.mergeMessages([message(2, "echo", eventSequence: 2)], into: conversationID(1))    // equal version → no dup
        let messages = store.messages(for: conversationID(1))
        #expect(messages.map(\.id.value) == [1, 2])
        #expect(messages.last?.content == .text("hi")) // equal event_sequence keeps the held copy
    }

    @Test("last-writer-wins: a lower event_sequence is ignored; a higher one replaces")
    func mergeLastWriterWins() {
        var store = ConversationStore()
        store.mergeMessages([message(1, "v2", eventSequence: 2)], into: conversationID(1))
        store.mergeMessages([message(1, "v1-stale", eventSequence: 1)], into: conversationID(1)) // older → ignored
        #expect(store.messages(for: conversationID(1)).first?.content == .text("v2"))
        store.mergeMessages([message(1, "v3", eventSequence: 3)], into: conversationID(1))        // newer → wins
        #expect(store.messages(for: conversationID(1)).first?.content == .text("v3"))
    }

    @Test("a delete tombstone replaces a prior message, and an out-of-order older send can't resurrect it")
    func deleteTombstoneConverges() {
        var store = ConversationStore()
        // Tombstone (event 10) lands before the original send (event 5) is re-delivered.
        store.mergeMessages([deleted(1, eventSequence: 10)], into: conversationID(1))
        store.mergeMessages([message(1, "original", eventSequence: 5)], into: conversationID(1))
        let first = store.messages(for: conversationID(1)).first
        #expect(first?.content == .deleted)   // stale older send never overwrites the newer tombstone
    }

    // MARK: - Event-log cursor & gap detection

    private func sentEvent(sequence: UInt64, count: UInt64 = 1, _ messages: ConversationMessage...) -> DecodedChatEvent {
        DecodedChatEvent(sequence: sequence, count: count, mutations: messages.map { .sent($0) })
    }

    /// One `.chatEvents` apply over the frontier arithmetic: an event is contiguous when
    /// `sequence == cursor + count` (advance the frontier), a hole otherwise (flag catch-up, hold the
    /// frontier), and stale when `sequence <= cursor` (ignore). `count` drives the math independently of
    /// how many mutations the event carries.
    @Test("gap detection advances the frontier only on a contiguous event", arguments: [
        (start: UInt64(5), sequence: UInt64(6), count: UInt64(1), expected: UInt64(6), gapped: false), // contiguous
        (start: 6, sequence: 9, count: 1, expected: 6, gapped: true),                                   // hole below the event
        (start: 10, sequence: 13, count: 3, expected: 13, gapped: false),                               // multi-mutation, contiguous
        (start: 10, sequence: 8, count: 1, expected: 10, gapped: false),                                // stale, ignored
    ])
    func gapDetection(start: UInt64, sequence: UInt64, count: UInt64, expected: UInt64, gapped: Bool) {
        var store = ConversationStore()
        store.setAppliedCursor(start, for: conversationID(1))
        let signal = store.apply(.chatEvents(conversationID: conversationID(1), events: [sentEvent(sequence: sequence, count: count, message(sequence, eventSequence: sequence))]))
        #expect(store.appliedCursor(for: conversationID(1)) == expected)
        let expectedSignal: ConversationStore.GapSignal = gapped ? .needsCatchUp(conversationID(1), after: expected) : .none
        #expect(signal == expectedSignal)
    }

    @Test("a gapped event's messages are still merged — LWW is independent of gap detection")
    func gappedEventStillMergesMessages() {
        var store = ConversationStore()
        store.setAppliedCursor(5, for: conversationID(1))
        store.apply(.chatEvents(conversationID: conversationID(1), events: [sentEvent(sequence: 6, message(6, eventSequence: 6))]))
        store.apply(.chatEvents(conversationID: conversationID(1), events: [sentEvent(sequence: 9, message(9, eventSequence: 9))])) // gap
        #expect(store.messages(for: conversationID(1)).map(\.id.value) == [6, 9])
    }

    @Test("an unestablished frontier applies messages by LWW without advancing or flagging a gap")
    func chatEventsUnestablishedFrontier() {
        var store = ConversationStore()
        let signal = store.apply(.chatEvents(conversationID: conversationID(1), events: [sentEvent(sequence: 42, message(42, eventSequence: 42))]))
        #expect(signal == .none)
        #expect(store.appliedCursor(for: conversationID(1)) == 0) // catch-up owns the cursor until seeded
        #expect(store.messages(for: conversationID(1)).map(\.id.value) == [42])
    }

    @Test("applyDeltaBatch merges and advances the frontier to the checkpoint; setAppliedCursor never regresses")
    func applyDeltaBatchAdvancesCursor() {
        var store = ConversationStore()
        store.applyDeltaBatch([message(1, eventSequence: 1), message(2, eventSequence: 2)], checkpoint: 2, into: conversationID(1))
        #expect(store.appliedCursor(for: conversationID(1)) == 2)
        #expect(store.messages(for: conversationID(1)).map(\.id.value) == [1, 2])
        store.setAppliedCursor(1, for: conversationID(1)) // lower → ignored
        #expect(store.appliedCursor(for: conversationID(1)) == 2)
        store.setAppliedCursor(9, for: conversationID(1)) // head → advances
        #expect(store.appliedCursor(for: conversationID(1)) == 9)
    }

    @Test("resetCursor discards the frontier; seedAppliedCursors restores non-zero cursors")
    func cursorResetAndSeed() {
        var store = ConversationStore()
        store.setAppliedCursor(7, for: conversationID(1))
        store.resetCursor(for: conversationID(1))
        #expect(store.appliedCursor(for: conversationID(1)) == 0)
        store.seedAppliedCursors([conversationID(1): 12, conversationID(2): 0])
        #expect(store.appliedCursor(for: conversationID(1)) == 12)
        #expect(store.appliedCursor(for: conversationID(2)) == 0) // zero ignored
    }

    @Test("an edit of an old message does not advance the feed's last message")
    func chatEventsEditDoesNotBumpLastMessage() {
        var store = ConversationStore()
        store.setFeed([conversation(1, lastActivity: 0)])
        store.mergeMessages([message(5, "old", eventSequence: 5)], into: conversationID(1))
        store.setLastMessage(message(5, "old", eventSequence: 5), in: conversationID(1))
        store.apply(.chatEvents(conversationID: conversationID(1), events: [
            DecodedChatEvent(sequence: 6, count: 1, mutations: [.edited(message(5, "edited", eventSequence: 6))])
        ]))
        #expect(store.conversations.first?.lastMessage?.id.value == 5)
        #expect(store.messages(for: conversationID(1)).first?.content == .text("edited")) // transcript updates by LWW
    }

    @Test("newMessages event appends and bumps the conversation's last activity")
    func applyNewMessages() {
        var store = ConversationStore()
        store.setFeed([conversation(1, lastActivity: 100), conversation(2, lastActivity: 200)])
        store.apply(.newMessages(conversationID: conversationID(1), messages: [message(5, "yo", at: 500)]))

        #expect(store.messages(for: conversationID(1)).map(\.id.value) == [5])
        // conversation 1 moves to the front after its new activity
        #expect(store.conversations.first?.id == conversationID(1))
        #expect(store.conversations.first?.lastMessage?.content == .text("yo"))
    }

    @Test("lastActivityChanged re-sorts the feed")
    func applyLastActivityChanged() {
        var store = ConversationStore()
        store.setFeed([conversation(1, lastActivity: 100), conversation(2, lastActivity: 200)])
        store.apply(.lastActivityChanged(conversationID: conversationID(1), date: Date(timeIntervalSince1970: 999)))
        #expect(store.conversations.first?.id == conversationID(1))
    }

    @Test("metadataRefresh upserts a new conversation")
    func applyMetadataRefreshInserts() {
        var store = ConversationStore()
        store.setFeed([conversation(1, lastActivity: 100)])
        store.apply(.metadataRefresh(conversation(2, lastActivity: 999)))
        #expect(store.conversations.count == 2)
        #expect(store.conversations.first?.id == conversationID(2))
    }

    @Test("readPointersChanged advances a member's READ watermark monotonically")
    func applyReadPointers() {
        let me = UUID()
        var store = ConversationStore()
        store.setFeed([Conversation(
            id: conversationID(1),
            members: [ConversationMember(userID: me, displayName: "", readPointer: MessageID(value: 2))],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0)
        )])

        store.apply(.readPointersChanged(conversationID: conversationID(1), pointers: [MemberReadPointer(userID: me, value: MessageID(value: 5))]))
        #expect(store.selfReadPointer(for: conversationID(1), selfUserID: me) == MessageID(value: 5))

        // A stale watermark never moves it backward.
        store.apply(.readPointersChanged(conversationID: conversationID(1), pointers: [MemberReadPointer(userID: me, value: MessageID(value: 3))]))
        #expect(store.selfReadPointer(for: conversationID(1), selfUserID: me) == MessageID(value: 5))
    }

    @Test("readPointersChanged stores the read time when the watermark advances, and leaves it on a stale update")
    func applyReadPointers_storesTimestamp() {
        let me = UUID()
        let readAt = Date(timeIntervalSince1970: 1_700_000_000)
        var store = ConversationStore()
        store.setFeed([Conversation(
            id: conversationID(1),
            members: [ConversationMember(userID: me, displayName: "", readPointer: MessageID(value: 2))],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0)
        )])

        store.apply(.readPointersChanged(conversationID: conversationID(1), pointers: [MemberReadPointer(userID: me, value: MessageID(value: 5), date: readAt)]))
        #expect(store.conversations.first?.members.first?.readPointerTimestamp == readAt)

        // A backward (stale) update is a no-op: the time stays put.
        store.apply(.readPointersChanged(conversationID: conversationID(1), pointers: [MemberReadPointer(userID: me, value: MessageID(value: 3), date: Date(timeIntervalSince1970: 0))]))
        #expect(store.conversations.first?.members.first?.readPointerTimestamp == readAt)
    }

    // MARK: - Feed preview from merge paths

    private func cashMessage(_ id: UInt64) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id),
            senderID: nil,
            content: .cash(ExchangedFiat(nativeAmount: .usd(5.00), rate: .oneToOne)),
            date: Date(timeIntervalSince1970: 0),
            unreadSeq: 0,
            eventSequence: id
        )
    }

    @Test("a merged send-cash message newer than the preview becomes the feed's last message")
    func mergeAdvancesPreviewToNewerCashMessage() {
        var store = ConversationStore()
        store.setFeed([conversation(1, lastActivity: 100)])
        store.mergeMessages([message(3, "old text")], into: conversationID(1))
        // The user's own cash send reaches the store via GetDelta catch-up — a merge-only path.
        let cash = cashMessage(7)
        store.applyDeltaBatch([cash], checkpoint: 7, into: conversationID(1))
        #expect(store.conversations.first?.lastMessage == cash)
    }

    @Test("a merge seeds the preview of a conversation that has none")
    func mergeSeedsMissingPreview() {
        var store = ConversationStore()
        store.setFeed([conversation(1, lastActivity: 100)])
        store.mergeMessages([message(4, "first")], into: conversationID(1))
        #expect(store.conversations.first?.lastMessage?.id.value == 4)
    }

    @Test("a paged-in older message does not regress the feed's last message")
    func mergeDoesNotRegressPreview() {
        var store = ConversationStore()
        store.setFeed([conversation(1, lastActivity: 100)])
        store.mergeMessages([message(9, "newest")], into: conversationID(1))
        store.mergeMessages([message(2, "older history")], into: conversationID(1))
        #expect(store.conversations.first?.lastMessage?.id.value == 9)
    }

    @Test("a merged tombstone is skipped — the newest visible message becomes the preview")
    func mergeSkipsTombstoneForPreview() {
        var store = ConversationStore()
        store.setFeed([conversation(1, lastActivity: 100)])
        store.mergeMessages([message(3, "old")], into: conversationID(1))
        store.applyDeltaBatch([message(6, "visible", eventSequence: 6), deleted(7, eventSequence: 7)], checkpoint: 7, into: conversationID(1))
        #expect(store.conversations.first?.lastMessage?.id.value == 6)
    }

    @Test("a merge advances the preview without re-sorting the feed — activity stays feed-owned")
    func mergeDoesNotResortFeed() {
        var store = ConversationStore()
        store.setFeed([conversation(1, lastActivity: 100), conversation(2, lastActivity: 200)])
        store.mergeMessages([message(5, "fresh", at: 500)], into: conversationID(1))
        #expect(store.conversations.map(\.id) == [conversationID(2), conversationID(1)])
        #expect(store.conversations.last?.lastMessage?.id.value == 5)
    }

    @Test("a stale re-delivered newMessages event does not regress the preview")
    func staleNewMessagesDoesNotRegressPreview() {
        var store = ConversationStore()
        store.setFeed([conversation(1, lastActivity: 100)])
        store.apply(.newMessages(conversationID: conversationID(1), messages: [message(10, "newest")]))
        store.apply(.newMessages(conversationID: conversationID(1), messages: [message(8, "stale re-delivery")]))
        #expect(store.conversations.first?.lastMessage?.id.value == 10)
    }

    @Test("a batch that sends and immediately deletes a message does not preview the deleted copy")
    func sendPlusDeleteBatchDoesNotResurrectPreview() {
        var store = ConversationStore()
        store.setFeed([conversation(1, lastActivity: 100)])
        store.mergeMessages([message(6, "visible", eventSequence: 6)], into: conversationID(1))
        store.apply(.chatEvents(conversationID: conversationID(1), events: [
            DecodedChatEvent(sequence: 7, count: 1, mutations: [.sent(message(7, "sent then deleted", eventSequence: 7))]),
            DecodedChatEvent(sequence: 8, count: 1, mutations: [.deleted(deleted(7, eventSequence: 8))]),
        ]))
        #expect(store.conversations.first?.lastMessage?.id.value == 6)
    }

    @Test("an edit of the preview message refreshes its content without moving the row")
    func editOfPreviewRefreshesContent() {
        var store = ConversationStore()
        store.setFeed([conversation(1, lastActivity: 100)])
        store.mergeMessages([message(5, "old", eventSequence: 5)], into: conversationID(1))
        store.apply(.chatEvents(conversationID: conversationID(1), events: [
            DecodedChatEvent(sequence: 6, count: 1, mutations: [.edited(message(5, "edited", eventSequence: 6))]),
        ]))
        #expect(store.conversations.first?.lastMessage?.id.value == 5)
        #expect(store.conversations.first?.lastMessage?.content == .text("edited"))
    }

    // MARK: - Optimistic send

    @Test("A server-built message defaults to .sent with no client id; stableID is the server id")
    func messageDefaultsAreSent() {
        let m = message(7)
        #expect(m.status == .sent)
        #expect(m.clientMessageID == nil)
        #expect(m.stableID == "7")
    }

    @Test("A pending message carries its client id as the stable identity")
    func pendingMessageStableID() {
        let id = UUID()
        let m = ConversationMessage(
            id: MessageID(value: .max), senderID: nil, content: .text("hi"),
            date: Date(timeIntervalSince1970: 0), unreadSeq: 0,
            status: .sending, clientMessageID: id
        )
        #expect(m.status == .sending)
        #expect(m.stableID == id.uuidString)
    }

    @Test("insertPending shows the optimistic message after the confirmed ones; messages() ignores it")
    func insertPendingDisplaysAfterConfirmed() {
        var store = ConversationStore()
        store.mergeMessages([message(1), message(2)], into: conversationID(1))
        let clientID = UUID()
        store.insertPending(
            ConversationMessage(id: MessageID(value: .max), senderID: nil, content: .text("c"),
                                date: Date(timeIntervalSince1970: 99), unreadSeq: 0,
                                status: .sending, clientMessageID: clientID),
            into: conversationID(1)
        )
        #expect(store.displayedMessages(for: conversationID(1)).map(\.stableID) == ["1", "2", clientID.uuidString])
        #expect(store.messages(for: conversationID(1)).map(\.id.value) == [1, 2]) // confirmed-only, unchanged
    }

    @Test("markPending flips a pending message to failed")
    func markPendingFailed() {
        var store = ConversationStore()
        let clientID = UUID()
        store.insertPending(
            ConversationMessage(id: MessageID(value: .max), senderID: nil, content: .text("c"),
                                date: Date(timeIntervalSince1970: 0), unreadSeq: 0,
                                status: .sending, clientMessageID: clientID),
            into: conversationID(1)
        )
        store.markPending(clientMessageID: clientID, status: .failed, in: conversationID(1))
        #expect(store.pendingMessage(clientMessageID: clientID, in: conversationID(1))?.status == .failed)
    }

    @Test("reconcile drops the pending copy and keeps the client id on the confirmed message")
    func reconcileKeepsIdentity() {
        var store = ConversationStore()
        let clientID = UUID()
        store.insertPending(
            ConversationMessage(id: MessageID(value: .max), senderID: nil, content: .text("c"),
                                date: Date(timeIntervalSince1970: 0), unreadSeq: 0,
                                status: .sending, clientMessageID: clientID),
            into: conversationID(1)
        )
        store.reconcile(clientMessageID: clientID, with: message(5, "c"), in: conversationID(1))

        let displayed = store.displayedMessages(for: conversationID(1))
        #expect(displayed.count == 1)
        #expect(displayed.first?.id.value == 5)
        #expect(displayed.first?.status == .sent)
        #expect(displayed.first?.stableID == clientID.uuidString)   // identity preserved → no re-insert
        #expect(store.pendingMessage(clientMessageID: clientID, in: conversationID(1)) == nil)
    }

    @Test("a stream echo of a reconciled message does not strip its client id")
    func mergePreservesClientID() {
        var store = ConversationStore()
        let clientID = UUID()
        store.insertPending(
            ConversationMessage(id: MessageID(value: .max), senderID: nil, content: .text("c"),
                                date: Date(timeIntervalSince1970: 0), unreadSeq: 0,
                                status: .sending, clientMessageID: clientID),
            into: conversationID(1)
        )
        store.reconcile(clientMessageID: clientID, with: message(5, "c"), in: conversationID(1))
        // The event stream re-delivers the same server message with no client id.
        store.mergeMessages([message(5, "c")], into: conversationID(1))

        let displayed = store.displayedMessages(for: conversationID(1))
        #expect(displayed.count == 1)
        #expect(displayed.first?.stableID == clientID.uuidString)
    }

    @Test("An echo arriving before reconcile collapses onto the pending row (no duplicate, stable id)")
    func echoBeforeReconcileCollapses() {
        let me = UUID()
        var store = ConversationStore()
        let clientID = UUID()
        store.insertPending(
            ConversationMessage(id: MessageID(value: .max), senderID: me, content: .text("c"),
                                date: Date(timeIntervalSince1970: 0), unreadSeq: 0,
                                status: .sending, clientMessageID: clientID),
            into: conversationID(1)
        )
        // The stream echo (server id, no client id, same sender+content+time) lands before the RPC.
        store.mergeMessages(
            [ConversationMessage(id: MessageID(value: 5), senderID: me, content: .text("c"),
                                 date: Date(timeIntervalSince1970: 1), unreadSeq: 0)],
            into: conversationID(1)
        )
        let displayed = store.displayedMessages(for: conversationID(1))
        #expect(displayed.count == 1)                               // collapsed, not duplicated
        #expect(displayed.first?.id.value == 5)
        #expect(displayed.first?.status == .sent)
        #expect(displayed.first?.stableID == clientID.uuidString)   // identity preserved across the echo
        #expect(store.pendingMessage(clientMessageID: clientID, in: conversationID(1)) == nil)
    }

    @Test("An echo reconciles a failed pending send, clearing the phantom (timed-out-but-persisted)")
    func echoReconcilesFailedPending() {
        let me = UUID()
        var store = ConversationStore()
        let clientID = UUID()
        store.insertPending(
            ConversationMessage(id: MessageID(value: .max), senderID: me, content: .text("c"),
                                date: Date(timeIntervalSince1970: 0), unreadSeq: 0,
                                status: .sending, clientMessageID: clientID),
            into: conversationID(1)
        )
        store.markPending(clientMessageID: clientID, status: .failed, in: conversationID(1))
        // The send RPC timed out, but the server persisted + echoed the message.
        store.mergeMessages(
            [ConversationMessage(id: MessageID(value: 5), senderID: me, content: .text("c"),
                                 date: Date(timeIntervalSince1970: 1), unreadSeq: 0)],
            into: conversationID(1)
        )
        let displayed = store.displayedMessages(for: conversationID(1))
        #expect(displayed.count == 1)                               // no permanent duplicate
        #expect(displayed.first?.status == .sent)                   // no false "Not Delivered" phantom
        #expect(store.pendingMessage(clientMessageID: clientID, in: conversationID(1)) == nil)
    }

    @Test("An unrelated old message with identical text does not reconcile a fresh pending send")
    func oldHistoryDoesNotReconcile() {
        let me = UUID()
        var store = ConversationStore()
        let clientID = UUID()
        store.insertPending(
            ConversationMessage(id: MessageID(value: .max), senderID: me, content: .text("hi"),
                                date: Date(timeIntervalSince1970: 100_000), unreadSeq: 0,
                                status: .sending, clientMessageID: clientID),
            into: conversationID(1)
        )
        // A history page carries an old "hi" from the same sender, far outside the reconcile window.
        store.mergeMessages(
            [ConversationMessage(id: MessageID(value: 5), senderID: me, content: .text("hi"),
                                 date: Date(timeIntervalSince1970: 0), unreadSeq: 0)],
            into: conversationID(1)
        )
        let displayed = store.displayedMessages(for: conversationID(1))
        #expect(displayed.count == 2)                               // distinct messages, not collapsed
        #expect(store.pendingMessage(clientMessageID: clientID, in: conversationID(1)) != nil)
    }

    @Test("A counterpart message with identical text does not reconcile a pending self-send")
    func counterpartMessageDoesNotReconcile() {
        let me = UUID(), them = UUID()
        var store = ConversationStore()
        let clientID = UUID()
        store.insertPending(
            ConversationMessage(id: MessageID(value: .max), senderID: me, content: .text("hi"),
                                date: Date(timeIntervalSince1970: 0), unreadSeq: 0,
                                status: .sending, clientMessageID: clientID),
            into: conversationID(1)
        )
        store.mergeMessages(
            [ConversationMessage(id: MessageID(value: 5), senderID: them, content: .text("hi"),
                                 date: Date(timeIntervalSince1970: 0), unreadSeq: 0)],
            into: conversationID(1)
        )
        let displayed = store.displayedMessages(for: conversationID(1))
        #expect(displayed.count == 2)                               // counterpart's "hi" + my pending "hi"
        #expect(store.pendingMessage(clientMessageID: clientID, in: conversationID(1)) != nil)
    }

    @Test("A re-delivered already-confirmed identical message does not absorb a fresh pending send")
    func redeliveredConfirmedDoesNotAbsorbPending() {
        let me = UUID()
        var store = ConversationStore()
        // An identical "hi" was sent earlier and confirmed at id 5.
        store.mergeMessages(
            [ConversationMessage(id: MessageID(value: 5), senderID: me, content: .text("hi"),
                                 date: Date(timeIntervalSince1970: 100), unreadSeq: 0)],
            into: conversationID(1)
        )
        // A fresh "hi" is now in flight, within the reconcile window of the old one.
        let clientID = UUID()
        store.insertPending(
            ConversationMessage(id: MessageID(value: .max), senderID: me, content: .text("hi"),
                                date: Date(timeIntervalSince1970: 120), unreadSeq: 0,
                                status: .sending, clientMessageID: clientID),
            into: conversationID(1)
        )
        // The stream re-delivers the OLD confirmed "hi" (id 5, already known) — it must not steal the
        // fresh pending row.
        store.mergeMessages(
            [ConversationMessage(id: MessageID(value: 5), senderID: me, content: .text("hi"),
                                 date: Date(timeIntervalSince1970: 100), unreadSeq: 0)],
            into: conversationID(1)
        )
        #expect(store.pendingMessage(clientMessageID: clientID, in: conversationID(1)) != nil)
        #expect(store.displayedMessages(for: conversationID(1)).count == 2)   // old confirmed + fresh pending
    }

    private func displayedTexts(_ store: ConversationStore, _ id: ConversationID) -> [String] {
        store.displayedMessages(for: id).map { if case .text(let t) = $0.content { t } else { "" } }
    }

    @Test("A failed send keeps its chronological place when newer messages arrive")
    func failedMessageHoldsChronologicalPosition() {
        let me = UUID()
        var store = ConversationStore()
        store.mergeMessages([message(1, "a"), message(2, "b"), message(3, "c")], into: conversationID(1))
        // Sent after seeing id 3, then it fails.
        let clientID = UUID()
        store.insertPending(
            ConversationMessage(id: MessageID(value: .max), senderID: me, content: .text("mine"),
                                date: Date(timeIntervalSince1970: 0), unreadSeq: 0,
                                status: .sending, clientMessageID: clientID),
            into: conversationID(1)
        )
        store.markPending(clientMessageID: clientID, status: .failed, in: conversationID(1))
        // A newer message arrives.
        store.mergeMessages([message(4, "later")], into: conversationID(1))
        // "mine" stays after id 3 (where it was sent), before the newer "later" — not dumped at the tail.
        #expect(displayedTexts(store, conversationID(1)) == ["a", "b", "c", "mine", "later"])
    }

    @Test("Out-of-order reconcile keeps optimistic sends in send order")
    func outOfOrderReconcileKeepsSendOrder() {
        let me = UUID()
        var store = ConversationStore()
        store.mergeMessages([message(3, "x")], into: conversationID(1))
        let clientA = UUID(), clientB = UUID()
        store.insertPending(
            ConversationMessage(id: MessageID(value: .max), senderID: me, content: .text("A"),
                                date: Date(timeIntervalSince1970: 0), unreadSeq: 0,
                                status: .sending, clientMessageID: clientA),
            into: conversationID(1)
        )
        store.insertPending(
            ConversationMessage(id: MessageID(value: .max), senderID: me, content: .text("B"),
                                date: Date(timeIntervalSince1970: 0), unreadSeq: 0,
                                status: .sending, clientMessageID: clientB),
            into: conversationID(1)
        )
        // B (sent second) reconciles first.
        store.reconcile(clientMessageID: clientB, with: message(4, "B"), in: conversationID(1))
        // A (sent first, still pending) stays above the just-confirmed B.
        #expect(displayedTexts(store, conversationID(1)) == ["x", "A", "B"])
    }

    @Test("Out-of-order reconcile: the earlier send confirming first keeps send order")
    func earlierSendReconcilingFirstKeepsSendOrder() {
        let me = UUID()
        var store = ConversationStore()
        store.mergeMessages([message(3, "x")], into: conversationID(1))
        let clientA = UUID(), clientB = UUID()
        store.insertPending(
            ConversationMessage(id: MessageID(value: .max), senderID: me, content: .text("A"),
                                date: Date(timeIntervalSince1970: 0), unreadSeq: 0,
                                status: .sending, clientMessageID: clientA),
            into: conversationID(1)
        )
        store.insertPending(
            ConversationMessage(id: MessageID(value: .max), senderID: me, content: .text("B"),
                                date: Date(timeIntervalSince1970: 0), unreadSeq: 0,
                                status: .sending, clientMessageID: clientB),
            into: conversationID(1)
        )
        // A (sent first) reconciles first — B must NOT jump above it.
        store.reconcile(clientMessageID: clientA, with: message(4, "A"), in: conversationID(1))
        #expect(displayedTexts(store, conversationID(1)) == ["x", "A", "B"])
    }

    @Test("An ambiguous echo of two identical-text in-flight sends is not cross-wired")
    func ambiguousIdenticalSendsAreNotCrossWired() {
        let me = UUID()
        var store = ConversationStore()
        let clientA = UUID(), clientB = UUID()
        store.insertPending(
            ConversationMessage(id: MessageID(value: .max), senderID: me, content: .text("hi"),
                                date: Date(timeIntervalSince1970: 0), unreadSeq: 0,
                                status: .sending, clientMessageID: clientA),
            into: conversationID(1)
        )
        store.insertPending(
            ConversationMessage(id: MessageID(value: .max), senderID: me, content: .text("hi"),
                                date: Date(timeIntervalSince1970: 0), unreadSeq: 0,
                                status: .sending, clientMessageID: clientB),
            into: conversationID(1)
        )
        // An echo of "hi" can't be told apart from either pending send — it must NOT reconcile.
        store.mergeMessages(
            [ConversationMessage(id: MessageID(value: 5), senderID: me, content: .text("hi"),
                                 date: Date(timeIntervalSince1970: 0), unreadSeq: 0)],
            into: conversationID(1)
        )
        #expect(store.pendingMessage(clientMessageID: clientA, in: conversationID(1)) != nil)
        #expect(store.pendingMessage(clientMessageID: clientB, in: conversationID(1)) != nil)
        // No two displayed rows share a stableID — no diff-corrupting duplicate identity.
        let ids = store.displayedMessages(for: conversationID(1)).map(\.stableID)
        #expect(Set(ids).count == ids.count)
    }
}
