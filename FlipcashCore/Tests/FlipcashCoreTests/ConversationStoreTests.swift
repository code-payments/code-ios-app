//
//  ConversationStoreTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import FlipcashCore

/// The store now holds only the feed, the optimistic (pending) overlay, and the catch-up cursor —
/// confirmed messages live in the database (their last-writer-wins reconciliation is covered by
/// `Database+ConversationsTests`). These tests cover the overlay positioning, the echo→pending
/// reconcile, and gap/cursor detection.
@Suite("ConversationStore overlay + cursor")
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

    private func pending(_ clientID: UUID, _ text: String, sender: UserID? = nil, at: TimeInterval = 0, status: SendStatus = .sending) -> ConversationMessage {
        ConversationMessage(id: MessageID(value: .max), senderID: sender, content: .text(text), date: Date(timeIntervalSince1970: at), unreadSeq: 0, status: status, clientMessageID: clientID)
    }

    private func displayedTexts(_ store: ConversationStore, _ id: ConversationID, over confirmed: [ConversationMessage]) -> [String] {
        store.displayedMessages(for: id, over: confirmed).map { if case .text(let t) = $0.content { t } else { "" } }
    }

    // MARK: - Feed

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

    @Test("advanceLastActivity moves the conversation to the front")
    func advanceActivityResorts() {
        var store = ConversationStore()
        store.setFeed([conversation(1, lastActivity: 100), conversation(2, lastActivity: 200)])
        store.advanceLastActivity(to: Date(timeIntervalSince1970: 999), in: conversationID(1))
        #expect(store.conversations.first?.id == conversationID(1))
    }

    @Test("setFeedPreview advances to a newer message and never regresses to an older one")
    func feedPreviewNeverRegresses() {
        var store = ConversationStore()
        store.setFeed([conversation(1, lastActivity: 100)])
        store.setFeedPreview(message(5, "newest"), in: conversationID(1))
        #expect(store.conversations.first?.lastMessage?.id.value == 5)
        store.setFeedPreview(message(2, "older"), in: conversationID(1))         // older → ignored
        #expect(store.conversations.first?.lastMessage?.id.value == 5)
        store.setFeedPreview(message(9, "newer"), in: conversationID(1))         // newer → wins
        #expect(store.conversations.first?.lastMessage?.id.value == 9)
    }

    @Test("setFeedPreview does not re-sort the feed — activity stays feed-owned")
    func previewDoesNotResort() {
        var store = ConversationStore()
        store.setFeed([conversation(1, lastActivity: 100), conversation(2, lastActivity: 200)])
        store.setFeedPreview(message(5, "fresh"), in: conversationID(1))
        #expect(store.conversations.map(\.id) == [conversationID(2), conversationID(1)])
        #expect(store.conversations.last?.lastMessage?.id.value == 5)
    }

    // MARK: - Optimistic overlay

    @Test("insertPending shows the optimistic message after its anchor; the confirmed window is unchanged")
    func insertPendingDisplaysAfterAnchor() {
        var store = ConversationStore()
        let confirmed = [message(1), message(2)]
        let clientID = UUID()
        store.insertPending(pending(clientID, "c"), anchoredTo: 2, into: conversationID(1))
        #expect(store.displayedMessages(for: conversationID(1), over: confirmed).map(\.stableID) == ["1", "2", clientID.uuidString])
    }

    @Test("markPending flips a pending message to failed")
    func markPendingFailed() {
        var store = ConversationStore()
        let clientID = UUID()
        store.insertPending(pending(clientID, "c"), anchoredTo: 0, into: conversationID(1))
        store.markPending(clientMessageID: clientID, status: .failed, in: conversationID(1))
        #expect(store.pendingMessage(clientMessageID: clientID, in: conversationID(1))?.status == .failed)
    }

    @Test("a failed send keeps its chronological place when newer messages arrive")
    func failedSendHoldsPosition() {
        var store = ConversationStore()
        let clientID = UUID()
        store.insertPending(pending(clientID, "mine"), anchoredTo: 3, into: conversationID(1))  // sent after id 3
        store.markPending(clientMessageID: clientID, status: .failed, in: conversationID(1))
        // A newer confirmed message arrives; the failed send stays after id 3, before id 4.
        let confirmed = [message(1, "a"), message(2, "b"), message(3, "c"), message(4, "later")]
        #expect(displayedTexts(store, conversationID(1), over: confirmed) == ["a", "b", "c", "mine", "later"])
    }

    @Test("a pending anchored older than the window surfaces at the head, not the tail")
    func pendingOlderThanWindowGoesToHead() {
        var store = ConversationStore()
        let clientID = UUID()
        store.insertPending(pending(clientID, "failed", status: .failed), anchoredTo: 3, into: conversationID(1))
        // The rendered window is the newest slice (ids 11...20) — the anchor (3) scrolled out.
        let window = (11...20).map { message(UInt64($0)) }
        let displayed = store.displayedMessages(for: conversationID(1), over: window)
        #expect(displayed.first?.stableID == clientID.uuidString)   // above the window, not dumped at the tail
        #expect(displayed.last?.id.value == 20)
    }

    // MARK: - Reconcile

    @Test("pendingMatch matches a send by sender+content+window without dropping it; dropPending commits")
    func pendingMatchThenDrop() {
        let me = UUID()
        var store = ConversationStore()
        let clientID = UUID()
        store.insertPending(pending(clientID, "c", sender: me, at: 0), anchoredTo: 0, into: conversationID(1))
        let echo = ConversationMessage(id: MessageID(value: 5), senderID: me, content: .text("c"), date: Date(timeIntervalSince1970: 1), unreadSeq: 0)
        #expect(store.pendingMatch(for: echo, in: conversationID(1), excluding: []) == clientID)
        // Matching is non-destructive: the pending row survives a failed persist.
        #expect(store.pendingMessage(clientMessageID: clientID, in: conversationID(1)) != nil)
        store.dropPending(clientMessageID: clientID, confirmedAt: echo.id, in: conversationID(1))
        #expect(store.pendingMessage(clientMessageID: clientID, in: conversationID(1)) == nil)   // committed
    }

    @Test("a claimed send is excluded so one echo can't match twice in a batch")
    func claimedSendExcluded() {
        let me = UUID()
        var store = ConversationStore()
        let clientID = UUID()
        store.insertPending(pending(clientID, "c", sender: me, at: 0), anchoredTo: 0, into: conversationID(1))
        let echo = ConversationMessage(id: MessageID(value: 5), senderID: me, content: .text("c"), date: Date(timeIntervalSince1970: 1), unreadSeq: 0)
        #expect(store.pendingMatch(for: echo, in: conversationID(1), excluding: [clientID]) == nil)
    }

    @Test("a counterpart message with identical text does not match a pending self-send")
    func counterpartDoesNotReconcile() {
        let me = UUID(), them = UUID()
        var store = ConversationStore()
        let clientID = UUID()
        store.insertPending(pending(clientID, "hi", sender: me, at: 0), anchoredTo: 0, into: conversationID(1))
        let counterpart = ConversationMessage(id: MessageID(value: 5), senderID: them, content: .text("hi"), date: Date(timeIntervalSince1970: 0), unreadSeq: 0)
        #expect(store.pendingMatch(for: counterpart, in: conversationID(1), excluding: []) == nil)
        #expect(store.pendingMessage(clientMessageID: clientID, in: conversationID(1)) != nil)   // untouched
    }

    @Test("an old message outside the reconcile window does not match a fresh pending send")
    func oldMessageOutsideWindowDoesNotReconcile() {
        let me = UUID()
        var store = ConversationStore()
        let clientID = UUID()
        store.insertPending(pending(clientID, "hi", sender: me, at: 100_000), anchoredTo: 0, into: conversationID(1))
        let old = ConversationMessage(id: MessageID(value: 5), senderID: me, content: .text("hi"), date: Date(timeIntervalSince1970: 0), unreadSeq: 0)
        #expect(store.pendingMatch(for: old, in: conversationID(1), excluding: []) == nil)     // far outside the 5-min window
    }

    @Test("two identical-text in-flight sends are not cross-wired by an ambiguous echo")
    func ambiguousSendsNotCrossWired() {
        let me = UUID()
        var store = ConversationStore()
        let clientA = UUID(), clientB = UUID()
        store.insertPending(pending(clientA, "hi", sender: me, at: 0), anchoredTo: 0, into: conversationID(1))
        store.insertPending(pending(clientB, "hi", sender: me, at: 0), anchoredTo: 0, into: conversationID(1))
        let echo = ConversationMessage(id: MessageID(value: 5), senderID: me, content: .text("hi"), date: Date(timeIntervalSince1970: 0), unreadSeq: 0)
        #expect(store.pendingMatch(for: echo, in: conversationID(1), excluding: []) == nil)    // ambiguous → leave both
        #expect(store.pendingMessage(clientMessageID: clientA, in: conversationID(1)) != nil)
        #expect(store.pendingMessage(clientMessageID: clientB, in: conversationID(1)) != nil)
    }

    @Test("a send anchored at 0 (no history at send time) stays at the tail once history lands")
    func unanchoredSendStaysAtTail() {
        let me = UUID()
        var store = ConversationStore()
        let clientID = UUID()
        // Sent while the conversation had no persisted rows (a fresh DB after the schema wipe).
        store.insertPending(pending(clientID, "hi", sender: me), anchoredTo: 0, into: conversationID(1))
        // The history page then lands and the window renders it.
        let window = (100...110).map { message(UInt64($0)) }
        let displayed = store.displayedMessages(for: conversationID(1), over: window)
        #expect(displayed.last?.stableID == clientID.uuidString)    // the send trails — newest thing the user did
        #expect(displayed.first?.id.value == 100)                    // history is not pushed below it
    }

    @Test("setFeedPreview(force:) allows the tombstoned-newest regression the guard otherwise blocks")
    func forcedPreviewRegression() {
        var store = ConversationStore()
        store.setFeed([Conversation(id: conversationID(1), members: [], lastMessage: message(10), lastActivity: Date(timeIntervalSince1970: 0))])
        let previous = message(9)
        store.setFeedPreview(previous, in: conversationID(1))                 // guard blocks the regression
        #expect(store.conversations.first?.lastMessage?.id.value == 10)
        store.setFeedPreview(previous, in: conversationID(1), force: true)    // newest was tombstoned → forced
        #expect(store.conversations.first?.lastMessage?.id.value == 9)
    }

    @Test("dropPending removes a send and keeps a later still-pending send in send order")
    func dropPendingKeepsSendOrder() {
        let me = UUID()
        var store = ConversationStore()
        let clientA = UUID(), clientB = UUID()
        store.insertPending(pending(clientA, "A", sender: me), anchoredTo: 3, into: conversationID(1))
        store.insertPending(pending(clientB, "B", sender: me), anchoredTo: 3, into: conversationID(1))
        // B (sent second) confirms first at id 4; A (sent first, still pending) must stay above it.
        store.dropPending(clientMessageID: clientB, confirmedAt: MessageID(value: 4), in: conversationID(1))
        let confirmed = [message(3, "x"), message(4, "B")]
        #expect(displayedTexts(store, conversationID(1), over: confirmed) == ["x", "A", "B"])
    }

    // MARK: - Cursor + gap detection

    private func sentEvent(sequence: UInt64, count: UInt64 = 1, _ messages: ConversationMessage...) -> DecodedChatEvent {
        DecodedChatEvent(sequence: sequence, count: count, mutations: messages.map { .sent($0) })
    }

    @Test("gap detection advances the frontier only on a contiguous event", arguments: [
        (start: UInt64(5), sequence: UInt64(6), count: UInt64(1), expected: UInt64(6), gapped: false),
        (start: 6, sequence: 9, count: 1, expected: 6, gapped: true),
        (start: 10, sequence: 13, count: 3, expected: 13, gapped: false),
        (start: 10, sequence: 8, count: 1, expected: 10, gapped: false),
    ])
    func gapDetection(start: UInt64, sequence: UInt64, count: UInt64, expected: UInt64, gapped: Bool) {
        var store = ConversationStore()
        store.setAppliedCursor(start, for: conversationID(1))
        let signal = store.apply(.chatEvents(conversationID: conversationID(1), events: [sentEvent(sequence: sequence, count: count, message(sequence, eventSequence: sequence))]))
        #expect(store.appliedCursor(for: conversationID(1)) == expected)
        let expectedSignal: ConversationStore.GapSignal = gapped ? .needsCatchUp(conversationID(1), after: expected) : .none
        #expect(signal == expectedSignal)
    }

    @Test("an unestablished frontier neither advances nor flags a gap")
    func unestablishedFrontier() {
        var store = ConversationStore()
        let signal = store.apply(.chatEvents(conversationID: conversationID(1), events: [sentEvent(sequence: 42, message(42, eventSequence: 42))]))
        #expect(signal == .none)
        #expect(store.appliedCursor(for: conversationID(1)) == 0)   // catch-up owns the cursor until seeded
    }

    @Test("chatEvents bumps the feed activity to the newest sent mutation")
    func chatEventsBumpsActivity() {
        var store = ConversationStore()
        store.setFeed([conversation(1, lastActivity: 0), conversation(2, lastActivity: 500)])
        store.apply(.chatEvents(conversationID: conversationID(1), events: [sentEvent(sequence: 1, message(9, at: 999))]))
        #expect(store.conversations.first?.id == conversationID(1))   // moved to the front by activity
    }

    @Test("setAppliedCursor never regresses; reset clears; seed restores non-zero cursors")
    func cursorLifecycle() {
        var store = ConversationStore()
        store.setAppliedCursor(7, for: conversationID(1))
        store.setAppliedCursor(3, for: conversationID(1))   // lower → ignored
        #expect(store.appliedCursor(for: conversationID(1)) == 7)
        store.setAppliedCursor(9, for: conversationID(1))   // higher → advances
        #expect(store.appliedCursor(for: conversationID(1)) == 9)
        store.resetCursor(for: conversationID(1))
        #expect(store.appliedCursor(for: conversationID(1)) == 0)
        store.seedAppliedCursors([conversationID(1): 12, conversationID(2): 0])
        #expect(store.appliedCursor(for: conversationID(1)) == 12)
        #expect(store.appliedCursor(for: conversationID(2)) == 0)   // zero ignored
    }

    @Test("reseatCursor forces the cursor regardless of monotonicity (failed-persist recovery)")
    func reseatCursorForces() {
        var store = ConversationStore()
        store.setAppliedCursor(9, for: conversationID(1))
        store.reseatCursor(3, for: conversationID(1))   // lowers it, unlike setAppliedCursor
        #expect(store.appliedCursor(for: conversationID(1)) == 3)
    }

    @Test("newMessages bumps the conversation's last activity")
    func newMessagesBumpsActivity() {
        var store = ConversationStore()
        store.setFeed([conversation(1, lastActivity: 100), conversation(2, lastActivity: 200)])
        store.apply(.newMessages(conversationID: conversationID(1), messages: [message(5, "yo", at: 500)]))
        #expect(store.conversations.first?.id == conversationID(1))
    }

    @Test("readPointersChanged advances a member's READ watermark monotonically")
    func readPointers() {
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
        store.apply(.readPointersChanged(conversationID: conversationID(1), pointers: [MemberReadPointer(userID: me, value: MessageID(value: 3))]))
        #expect(store.selfReadPointer(for: conversationID(1), selfUserID: me) == MessageID(value: 5))   // never backward
    }

    @Test("hasPendingMessages reflects only the optimistic overlay")
    func hasPending() {
        var store = ConversationStore()
        #expect(!store.hasPendingMessages(for: conversationID(1)))
        let clientID = UUID()
        store.insertPending(pending(clientID, "c"), anchoredTo: 0, into: conversationID(1))
        #expect(store.hasPendingMessages(for: conversationID(1)))
    }
}
