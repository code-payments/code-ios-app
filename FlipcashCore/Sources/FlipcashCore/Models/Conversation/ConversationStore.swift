//
//  ConversationStore.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Pure, value-semantic store of the in-memory conversation state that is NOT the persisted transcript:
/// the feed (sorted by last activity), the optimistic (pending) send overlay, and the event-log
/// catch-up cursor. Confirmed messages live in the database — the transcript reads a bounded window
/// from there and the store's overlay is interleaved onto it at read time. Kept free of a controller,
/// network, or actor so the overlay + cursor logic stays unit-testable in isolation.
public struct ConversationStore: Sendable {

    public private(set) var conversations: [Conversation] = []
    /// Optimistic messages not yet confirmed by the server. Each carries the server id it was sent
    /// after (its `anchor`) and a monotonic send `sequence`, so the transcript orders it relative to
    /// confirmed rows without comparing client and server wall-clock times.
    private var pendingByConversation: [ConversationID: [PendingEntry]] = [:]
    /// Monotonic counter stamped on each optimistic send, breaking ties among rows that share an anchor
    /// and keeping send order stable across out-of-order reconciles.
    private var pendingSequence: UInt64 = 0
    /// The highest contiguous event-log `sequence` applied per conversation — the frontier passed to
    /// `GetDelta` as `after_sequence`. Zero means "not yet established"; a catch-up seeds it, after
    /// which live events advance it and gap-detect against it. Distinct from a message's `MessageId`
    /// and from any per-message `eventSequence`.
    private var appliedCursorByConversation: [ConversationID: UInt64] = [:]

    /// An optimistic send plus the keys that place it in the transcript: `anchor` is the newest
    /// confirmed server id at send time (the row this send sits after), `sequence` is its send order.
    private struct PendingEntry: Sendable {
        var message: ConversationMessage
        /// Re-anchored upward when an earlier-but-later-confirming sibling reconciles, so send order
        /// holds regardless of which concurrent send the server confirms first.
        var anchor: UInt64
        let sequence: UInt64
    }

    public init() {}

    /// Replace the feed from a paged load, sorted most-recent-activity first.
    public mutating func setFeed(_ conversations: [Conversation]) {
        self.conversations = conversations.sorted { $0.lastActivity > $1.lastActivity }
    }

    /// Replace one type's conversations from that type's paged feed load,
    /// leaving the other types' conversations in place. Rows of a different
    /// type are ignored — the call describes exactly one type's set.
    public mutating func setFeed(_ conversations: [Conversation], type: ConversationType) {
        let others = self.conversations.filter { $0.type != type }
        setFeed(others + conversations.filter { $0.type == type })
    }

    /// How far apart an incoming server copy and a pending optimistic send may be (in either
    /// direction, to absorb client/server clock skew) and still be treated as the same message. Wide
    /// enough for skew, tight enough that an unrelated old history message with identical text never
    /// reconciles a fresh pending send.
    private static let pendingReconcileWindow: TimeInterval = 5 * 60

    // MARK: - Transcript overlay

    /// Interleaves the conversation's optimistic overlay onto a caller-supplied confirmed window (read
    /// from the database) — each pending row right after the confirmed row it was sent after (its
    /// anchor), ties by send sequence, trailing pending after the last confirmed row. Ordering by the
    /// server `MessageId` anchor — not wall-clock dates — means a fresh send lands at the tail (immune
    /// to clock skew), a failed send keeps its place as newer messages arrive, and out-of-order
    /// reconciles never reshuffle.
    public func displayedMessages(for conversationID: ConversationID, over confirmed: [ConversationMessage]) -> [ConversationMessage] {
        guard let pending = pendingByConversation[conversationID], !pending.isEmpty else { return confirmed }

        // An anchor of 0 means the send predates any loaded history — it is the newest thing the user
        // did, so it belongs at the tail with the other unmatched fresh sends, not above history that
        // lands afterward. Sorting it as +∞ places it after every real anchor.
        let effectiveAnchor: (PendingEntry) -> UInt64 = { $0.anchor == 0 ? .max : $0.anchor }
        let ordered = pending.sorted { (effectiveAnchor($0), $0.sequence) < (effectiveAnchor($1), $1.sequence) }
        var result: [ConversationMessage] = []
        result.reserveCapacity(confirmed.count + ordered.count)
        var p = 0
        // A pending anchored older than this window (its anchor row scrolled out of the newest-N slice)
        // belongs above the window, not at the tail — surface it at the head in send order.
        let windowFloor = confirmed.first?.id.value ?? .max
        while p < ordered.count, effectiveAnchor(ordered[p]) < windowFloor {
            result.append(ordered[p].message)
            p += 1
        }
        for message in confirmed {
            result.append(message)
            while p < ordered.count, ordered[p].anchor == message.id.value {
                result.append(ordered[p].message)
                p += 1
            }
        }
        // Anything anchored beyond the last confirmed row (the common fresh-send case, or a send made
        // when no messages were loaded) trails at the end, in send order.
        while p < ordered.count {
            result.append(ordered[p].message)
            p += 1
        }
        return result
    }

    // MARK: - Optimistic (pending) sends

    /// Whether the conversation has an in-flight optimistic send. (Confirmed emptiness is a database
    /// question, answered by the controller.)
    public func hasPendingMessages(for conversationID: ConversationID) -> Bool {
        !(pendingByConversation[conversationID]?.isEmpty ?? true)
    }

    /// Add an optimistic message the server hasn't confirmed yet, anchored to the caller-supplied
    /// newest confirmed id at send time so the transcript can position it without a wall-clock compare.
    public mutating func insertPending(_ message: ConversationMessage, anchoredTo anchor: UInt64, into conversationID: ConversationID) {
        pendingByConversation[conversationID, default: []].append(PendingEntry(message: message, anchor: anchor, sequence: pendingSequence))
        pendingSequence += 1
    }

    /// The in-flight optimistic message for a client id, if still pending.
    public func pendingMessage(clientMessageID: UUID, in conversationID: ConversationID) -> ConversationMessage? {
        pendingByConversation[conversationID]?.first { $0.message.clientMessageID == clientMessageID }?.message
    }

    /// Move a pending message between sending and failed.
    public mutating func markPending(clientMessageID: UUID, status: SendStatus, in conversationID: ConversationID) {
        guard let index = pendingByConversation[conversationID]?.firstIndex(where: { $0.message.clientMessageID == clientMessageID }) else { return }
        pendingByConversation[conversationID]?[index].message.status = status
    }

    /// Match a server copy against the pending optimistic sends WITHOUT removing anything, returning
    /// the matched send's client id so the caller can carry that identity onto the persisted confirmed
    /// row (the echo collapses onto the send instead of duplicating it). The pending row is removed
    /// separately — via ``dropPending(clientMessageID:confirmedAt:in:)`` — only after the write that
    /// persists the copy succeeds, so a failed write never loses the send from the transcript. Returns
    /// nil when nothing matches (a counterpart message, or an unrelated history message); `claimed`
    /// excludes sends already matched earlier in the same batch. The caller gates this on the id being
    /// a *fresh* server id (not already persisted) so an old identical re-delivery never steals a send.
    public func pendingMatch(for serverCopy: ConversationMessage, in conversationID: ConversationID, excluding claimed: Set<UUID>) -> UUID? {
        guard let pending = pendingByConversation[conversationID] else { return nil }
        let matches = pending.filter {
            $0.message.senderID == serverCopy.senderID
                && $0.message.content == serverCopy.content
                && abs($0.message.date.timeIntervalSince(serverCopy.date)) < Self.pendingReconcileWindow
                && $0.message.clientMessageID.map { !claimed.contains($0) } ?? false
        }
        // Reconcile only an unambiguous match. Two in-flight sends with identical text can't be told
        // apart (the server echoes no client id), so leave them for their own send-RPC responses —
        // which key on the exact client id — rather than cross-wiring one send's id onto the other's row.
        guard matches.count == 1 else { return nil }
        return matches[0].message.clientMessageID
    }

    /// Drop a pending send confirmed by the send RPC's own response (keyed on the exact client id) and
    /// re-anchor any later still-pending send to the now-confirmed id, so send order holds even when an
    /// earlier send confirms after a later one.
    public mutating func dropPending(clientMessageID: UUID, confirmedAt confirmedID: MessageID, in conversationID: ConversationID) {
        let reconciledSequence = pendingByConversation[conversationID]?.first { $0.message.clientMessageID == clientMessageID }?.sequence
        pendingByConversation[conversationID]?.removeAll { $0.message.clientMessageID == clientMessageID }
        if let reconciledSequence {
            reanchorLaterSends(after: reconciledSequence, toAtLeast: confirmedID.value, in: conversationID)
        }
    }

    /// After an optimistic send (`sequence`) confirms at `confirmedID`, any still-pending send made
    /// after it (higher sequence) was sent after that now-confirmed row, so re-anchor it to at least
    /// `confirmedID`.
    private mutating func reanchorLaterSends(after sequence: UInt64, toAtLeast confirmedID: UInt64, in conversationID: ConversationID) {
        guard var pending = pendingByConversation[conversationID] else { return }
        for i in pending.indices where pending[i].sequence > sequence && pending[i].anchor < confirmedID {
            pending[i].anchor = confirmedID
        }
        pendingByConversation[conversationID] = pending
    }

    // MARK: - Feed

    /// The signed-in user's READ watermark for a conversation, as last reported by the feed/stream and
    /// locally advanced after each successful markRead.
    public func selfReadPointer(for conversationID: ConversationID, selfUserID: UserID) -> MessageID? {
        conversations.first { $0.id == conversationID }?.selfReadPointer(for: selfUserID)
    }

    /// Locally advance the signed-in user's READ watermark after a successful markRead so the next call
    /// can short-circuit.
    public mutating func advanceSelfReadPointer(to messageID: MessageID, in conversationID: ConversationID, selfUserID: UserID) {
        // Self's read time is never surfaced — only the counterpart's receipt shows one — so advance
        // the watermark without a timestamp.
        advanceReadPointer(to: messageID, for: selfUserID, at: nil, in: conversationID)
    }

    /// Monotonically advance a member's READ watermark; never moves it backward. `date` is when the
    /// pointer was advanced (for the read receipt); stored only when the watermark actually moves.
    private mutating func advanceReadPointer(to messageID: MessageID, for userID: UserID, at date: Date?, in conversationID: ConversationID) {
        guard let convoIndex = conversations.firstIndex(where: { $0.id == conversationID }),
              let memberIndex = conversations[convoIndex].members.firstIndex(where: { $0.userID == userID }) else {
            return
        }
        if let current = conversations[convoIndex].members[memberIndex].readPointer, messageID <= current {
            return
        }
        conversations[convoIndex].members[memberIndex].readPointer = messageID
        conversations[convoIndex].members[memberIndex].readPointerTimestamp = date
    }

    /// Bump a conversation's last activity and re-sort the feed. No-ops for a conversation not in the
    /// feed.
    public mutating func advanceLastActivity(to date: Date, in conversationID: ConversationID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[index].lastActivity = date
        sort()
    }

    /// Set the feed row's preview to the caller-supplied newest visible message (computed from the
    /// database), never regressing: an older or equal-versioned candidate is ignored, so a stale
    /// re-delivery can't overwrite a newer preview. `force` bypasses the guard for the one legitimate
    /// regression — the newest message was tombstoned, so the preview must fall back to the previous
    /// visible one instead of showing deleted content. Never touches `lastActivity` or the feed order.
    public mutating func setFeedPreview(_ newest: ConversationMessage?, in conversationID: ConversationID, force: Bool = false) {
        guard let newest, let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        if !force,
           let current = conversations[index].lastMessage,
           (current.id, current.eventSequence) >= (newest.id, newest.eventSequence) { return }
        conversations[index].lastMessage = newest
    }

    // MARK: - Live events (cursor + gap detection + feed activity)

    /// Signals whether applying a live event exposed a hole in the sequenced log that must be filled
    /// from `GetDelta`. Only `.chatEvents` can raise `.needsCatchUp`; every other event returns `.none`.
    public enum GapSignal: Sendable, Equatable {
        case none
        case needsCatchUp(ConversationID, after: UInt64)
    }

    /// Apply a live event's non-message effects: catch-up cursor + gap detection, feed activity, read
    /// pointers, and metadata. The confirmed messages themselves are persisted to the database by the
    /// controller — the store no longer holds them. Returns a gap signal so the controller can trigger a
    /// `GetDelta` catch-up when the sequenced log skipped ahead.
    @discardableResult
    public mutating func apply(_ event: ConversationStreamEvent) -> GapSignal {
        switch event {
        case .newMessages(let conversationID, let messages):
            if let latest = messages.max(by: { $0.id < $1.id }) {
                advanceLastActivity(to: latest.date, in: conversationID)
            }
            return .none
        case .chatEvents(let conversationID, let events):
            return applyChatEvents(events, into: conversationID)
        case .metadataRefresh(let conversation):
            upsert(conversation)
            return .none
        case .lastActivityChanged(let conversationID, let date):
            advanceLastActivity(to: date, in: conversationID)
            return .none
        case .readPointersChanged(let conversationID, let pointers):
            for pointer in pointers {
                advanceReadPointer(to: pointer.value, for: pointer.userID, at: pointer.date, in: conversationID)
            }
            return .none
        case .typingChanged:
            // Typing is ephemeral UI state held by the controller, never the persisted message store.
            return .none
        }
    }

    /// Advance the contiguous event-log frontier while events arrive gapless and flag a gap the moment
    /// one is skipped so the caller catches up via `GetDelta`; bump the feed activity to the newest
    /// `.sent` mutation (an edit/delete carries the message's original low id and must not move the row).
    private mutating func applyChatEvents(_ events: [DecodedChatEvent], into conversationID: ConversationID) -> GapSignal {
        var cursor = appliedCursorByConversation[conversationID] ?? 0
        var newestSent: ConversationMessage?
        var gapAfter: UInt64?

        for event in events.sorted(by: { $0.sequence < $1.sequence }) {
            for case .sent(let message) in event.mutations {
                if newestSent.map({ message.id > $0.id }) ?? true { newestSent = message }
            }

            // Gap-detect only once the frontier is established (a catch-up seeds it); before that, live
            // events are applied by the DB and the initial GetDelta owns the cursor.
            guard gapAfter == nil, cursor > 0 else { continue }
            if event.sequence <= cursor {
                continue // already applied — a duplicate/stale re-delivery, persisted harmlessly
            }
            if event.sequence == cursor + event.count {
                cursor = event.sequence // contiguous — advance the frontier
            } else {
                gapAfter = cursor // hole below this event; stop advancing and catch up from here
            }
        }

        appliedCursorByConversation[conversationID] = cursor
        if let newestSent {
            advanceLastActivity(to: newestSent.date, in: conversationID)
        }
        return gapAfter.map { .needsCatchUp(conversationID, after: $0) } ?? .none
    }

    // MARK: - Event-log catch-up cursor

    /// The frontier to pass as `GetDelta.after_sequence` for a conversation (zero = fetch from the
    /// beginning of the retained log).
    public func appliedCursor(for conversationID: ConversationID) -> UInt64 {
        appliedCursorByConversation[conversationID] ?? 0
    }

    /// Seat the frontier to the head reported by a cleanly-completed `GetDelta` — authoritative even
    /// though the client never observed the intervening contiguous events. Never regresses it.
    public mutating func setAppliedCursor(_ value: UInt64, for conversationID: ConversationID) {
        if value > appliedCursor(for: conversationID) {
            appliedCursorByConversation[conversationID] = value
        }
    }

    /// Discard the frontier (a `RESET_REQUIRED`): the next catch-up re-syncs history and re-establishes
    /// the cursor from a fresh floor.
    public mutating func resetCursor(for conversationID: ConversationID) {
        appliedCursorByConversation[conversationID] = 0
    }

    /// Force the in-memory cursor to a value regardless of monotonicity — used to recover from a failed
    /// message persist by re-seating from the (rolled-back) DB value, so a catch-up refetches the
    /// un-persisted window instead of skipping it.
    public mutating func reseatCursor(_ value: UInt64, for conversationID: ConversationID) {
        appliedCursorByConversation[conversationID] = value
    }

    /// Seed frontiers from the persisted cache at hydrate time. Ignores zero (unestablished) cursors.
    public mutating func seedAppliedCursors(_ cursors: [ConversationID: UInt64]) {
        for (conversationID, cursor) in cursors where cursor > 0 {
            appliedCursorByConversation[conversationID] = cursor
        }
    }

    private mutating func upsert(_ conversation: Conversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        } else {
            conversations.append(conversation)
        }
        sort()
    }

    private mutating func sort() {
        conversations.sort { $0.lastActivity > $1.lastActivity }
    }
}
