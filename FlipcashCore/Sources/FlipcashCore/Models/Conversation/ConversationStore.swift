//
//  ConversationStore.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Pure, value-semantic store of conversation state: the feed (sorted by last
/// activity) and the messages of open conversations. All reconciliation of
/// paged loads and live `ConversationStreamEvent`s happens here so it is
/// unit-testable in isolation, without a controller, network, or actor.
public struct ConversationStore: Sendable {

    public private(set) var conversations: [Conversation] = []
    private var messagesByConversation: [ConversationID: [ConversationMessage]] = [:]
    /// Optimistic messages not yet confirmed by the server, kept separate from the server-mirrored
    /// `messagesByConversation` so paging, mark-read, and the feed never see them. Each carries the
    /// server id it was sent after (its `anchor`) and a monotonic send `sequence`, so the transcript
    /// orders it relative to confirmed rows without comparing client and server wall-clock times.
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

    public func messages(for conversationID: ConversationID) -> [ConversationMessage] {
        messagesByConversation[conversationID] ?? []
    }

    /// Drops all but the newest `count` confirmed messages for a conversation. Called when the
    /// transcript is left so a paged-back thread doesn't retain its whole history in memory for the
    /// session. Pending sends and the applied cursor are untouched, and the feed preview is the
    /// newest message either way — older history re-pages from the server on reopen.
    public mutating func trimMessages(for conversationID: ConversationID, keepingNewest count: Int) {
        guard let messages = messagesByConversation[conversationID], messages.count > count else { return }
        messagesByConversation[conversationID] = Array(messages.suffix(count))
    }

    /// Replace the feed from a paged load, sorted most-recent-activity first.
    public mutating func setFeed(_ conversations: [Conversation]) {
        self.conversations = conversations.sorted { $0.lastActivity > $1.lastActivity }
    }

    /// How far apart an incoming server copy and a pending optimistic send may be (in either
    /// direction, to absorb client/server clock skew) and still be treated as the same message. Wide
    /// enough for skew, tight enough that an unrelated old history message with identical text never
    /// reconciles a fresh pending send.
    private static let pendingReconcileWindow: TimeInterval = 5 * 60

    /// Insert/replace messages keyed by their gapless id, keeping oldest first, applying
    /// last-writer-wins by `eventSequence`. A strictly-newer version (edit, delete, re-fetch) replaces
    /// the held copy; an older one is ignored; an equal one keeps the held copy. This makes a message
    /// self-locating regardless of delivery path (stream, history load, `GetDelta`, or the send RPC)
    /// and makes an out-of-order delete converge — a tombstone that lands before the original send
    /// out-versions it and is never overwritten. Reconciles a server copy of one of our own optimistic
    /// sends — which carries no client id, because the server never echoes it — against the matching
    /// pending row so the echo collapses onto that row instead of duplicating it. Every merge also
    /// advances the conversation's feed preview to the newest visible message.
    public mutating func mergeMessages(_ incoming: [ConversationMessage], into conversationID: ConversationID) {
        guard !incoming.isEmpty else { return }
        let current = messagesByConversation[conversationID] ?? []

        var byID = Dictionary(
            current.map { ($0.id, $0) },
            uniquingKeysWith: { _, new in new }
        )
        for message in incoming {
            var message = message
            let existing = byID[message.id]

            // A brand-new server id with no client id may be the echo of one of our pending sends —
            // adopt that pending row's client id (dropping the pending copy) so identity survives
            // sending → sent. Only a genuinely new id can be a fresh echo, so an old identical
            // re-delivery never steals a pending send.
            if message.clientMessageID == nil, existing == nil,
               let clientMessageID = reconcilePendingMatch(for: message, in: conversationID) {
                message.clientMessageID = clientMessageID
            }

            guard let existing else {
                byID[message.id] = message
                continue
            }

            if message.eventSequence > existing.eventSequence {
                // Newer version wins. Preserve the row's stable identity if the newer copy lacks one.
                if message.clientMessageID == nil {
                    message.clientMessageID = existing.clientMessageID
                }
                byID[message.id] = message
            } else if message.eventSequence == existing.eventSequence, existing.clientMessageID == nil,
                      let clientMessageID = message.clientMessageID {
                // Same version, but this copy carries the client id the held one lacks (a reconcile copy
                // landing after a stream echo, or vice versa). Adopt the id so the transcript diff keeps
                // one stable identity instead of re-inserting the row.
                var kept = existing
                kept.clientMessageID = clientMessageID
                byID[message.id] = kept
            }
            // Otherwise the held copy is newer-or-equal-and-already-identified: keep it.
        }
        messagesByConversation[conversationID] = byID.values.sorted { $0.id < $1.id }
        advanceLastMessage(in: conversationID)
    }

    /// Points the feed row's preview at the newest non-deleted confirmed message, mirroring the
    /// visibility filter and last-writer-wins guard of the persisted cache (`Database.latestMessage`
    /// / `writeMessage`) — it advances forward or refreshes an edit in place, never regresses, and
    /// never touches `lastActivity` or the feed order.
    private mutating func advanceLastMessage(in conversationID: ConversationID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }),
              let newest = messagesByConversation[conversationID]?.last(where: { $0.content != .deleted })
        else { return }
        if let current = conversations[index].lastMessage,
           (current.id, current.eventSequence) >= (newest.id, newest.eventSequence) { return }
        conversations[index].lastMessage = newest
    }

    /// Removes and returns the client id of the oldest pending send that matches `serverCopy` by sender
    /// and content within the reconcile window — the optimistic row this server copy confirms. Returns
    /// nil when nothing matches (a counterpart message, or an unrelated history message).
    private mutating func reconcilePendingMatch(for serverCopy: ConversationMessage, in conversationID: ConversationID) -> UUID? {
        guard var pending = pendingByConversation[conversationID] else { return nil }
        let matches = pending.indices.filter {
            pending[$0].message.senderID == serverCopy.senderID
                && pending[$0].message.content == serverCopy.content
                && abs(pending[$0].message.date.timeIntervalSince(serverCopy.date)) < Self.pendingReconcileWindow
        }
        // Reconcile only an unambiguous match. Two in-flight sends with identical text can't be told
        // apart (the server echoes no client id), so leave them for their own send-RPC responses —
        // which key on the exact client id — rather than cross-wiring one send's id onto the other's
        // row (which would briefly give two rows the same stableID).
        guard matches.count == 1, let index = matches.first else { return nil }
        let matched = pending.remove(at: index)
        pendingByConversation[conversationID] = pending
        reanchorLaterSends(after: matched.sequence, toAtLeast: serverCopy.id.value, in: conversationID)
        return matched.message.clientMessageID
    }

    /// After an optimistic send (`sequence`) confirms at `confirmedID`, any still-pending send made
    /// after it (higher sequence) was sent after that now-confirmed row, so re-anchor it to at least
    /// `confirmedID`. This keeps send order even when an earlier send reconciles before a later one.
    private mutating func reanchorLaterSends(after sequence: UInt64, toAtLeast confirmedID: UInt64, in conversationID: ConversationID) {
        guard var pending = pendingByConversation[conversationID] else { return }
        for i in pending.indices where pending[i].sequence > sequence && pending[i].anchor < confirmedID {
            pending[i].anchor = confirmedID
        }
        pendingByConversation[conversationID] = pending
    }

    // MARK: - Optimistic (pending) sends

    /// The transcript's source of truth: confirmed rows in server order, with each in-flight optimistic
    /// row placed right after the confirmed row it was sent after (its anchor), ties broken by send
    /// sequence. Ordering by the server `MessageId` anchor — not wall-clock dates — means a fresh send
    /// lands at the tail (immune to clock skew, scroll-to-bottom stays reliable), a failed send keeps
    /// its place even as newer messages arrive, and out-of-order reconciles never reshuffle (a
    /// reconciled row's real id is greater than its anchor, so it lands where the pending row was).
    /// `messages(for:)` stays confirmed-only for mark-read and paging.
    public func displayedMessages(for conversationID: ConversationID) -> [ConversationMessage] {
        let confirmed = messagesByConversation[conversationID] ?? []
        guard let pending = pendingByConversation[conversationID], !pending.isEmpty else { return confirmed }

        let ordered = pending.sorted { ($0.anchor, $0.sequence) < ($1.anchor, $1.sequence) }
        var result: [ConversationMessage] = []
        result.reserveCapacity(confirmed.count + ordered.count)
        var p = 0
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

    /// The newest server-confirmed message, or nil. Confirmed rows are kept sorted oldest-first and are
    /// always `.sent` (pending sends live separately), so this is what the receive buzz and mark-read
    /// track — never a pending row.
    public func lastConfirmedMessage(for conversationID: ConversationID) -> ConversationMessage? {
        messagesByConversation[conversationID]?.last
    }

    /// Whether the conversation has any message (confirmed or in-flight) — checked without building the
    /// merged transcript, so an emptiness test doesn't allocate the whole array.
    public func hasMessages(for conversationID: ConversationID) -> Bool {
        !(messagesByConversation[conversationID]?.isEmpty ?? true) || !(pendingByConversation[conversationID]?.isEmpty ?? true)
    }

    /// Add an optimistic message that the server hasn't confirmed yet, anchored to the newest confirmed
    /// id at send time so the transcript can position it without a wall-clock comparison.
    public mutating func insertPending(_ message: ConversationMessage, into conversationID: ConversationID) {
        let anchor = messagesByConversation[conversationID]?.last?.id.value ?? 0
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

    /// Replace a server-confirmed send (the send RPC's own response): drop the optimistic copy and merge
    /// the server message, carrying the client id onto it so the row keeps its identity across
    /// sending → sent (no delete+insert).
    public mutating func reconcile(clientMessageID: UUID, with serverMessage: ConversationMessage, in conversationID: ConversationID) {
        let reconciledSequence = pendingByConversation[conversationID]?.first { $0.message.clientMessageID == clientMessageID }?.sequence
        pendingByConversation[conversationID]?.removeAll { $0.message.clientMessageID == clientMessageID }
        var confirmed = serverMessage
        confirmed.status = .sent
        confirmed.clientMessageID = clientMessageID
        mergeMessages([confirmed], into: conversationID)
        if let reconciledSequence {
            reanchorLaterSends(after: reconciledSequence, toAtLeast: serverMessage.id.value, in: conversationID)
        }
    }

    /// The signed-in user's READ watermark for a conversation, as last reported by
    /// the feed/stream and locally advanced after each successful markRead.
    public func selfReadPointer(for conversationID: ConversationID, selfUserID: UserID) -> MessageID? {
        conversations.first { $0.id == conversationID }?.selfReadPointer(for: selfUserID)
    }

    /// Locally advance the signed-in user's READ watermark after a successful
    /// markRead so the next call can short-circuit.
    public mutating func advanceSelfReadPointer(to messageID: MessageID, in conversationID: ConversationID, selfUserID: UserID) {
        // Self's read time is never surfaced — only the counterpart's receipt
        // shows one — so advance the watermark without a timestamp.
        advanceReadPointer(to: messageID, for: selfUserID, at: nil, in: conversationID)
    }

    /// Monotonically advance a member's READ watermark; never moves it backward.
    /// `date` is when the pointer was advanced (for the read receipt); stored
    /// only when the watermark actually moves.
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

    /// Bump a conversation's last activity from a live message and re-sort the feed. The preview
    /// itself follows the merge rule (``advanceLastMessage``), so a stale re-delivery or a deleted
    /// copy on the live path can't overwrite a newer one.
    public mutating func setLastMessage(_ message: ConversationMessage, in conversationID: ConversationID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[index].lastActivity = message.date
        sort()
        advanceLastMessage(in: conversationID)
    }

    /// Signals whether applying a live event exposed a hole in the sequenced log that must be filled
    /// from `GetDelta`. Only `.chatEvents` can raise `.needsCatchUp`; every other event returns `.none`.
    public enum GapSignal: Sendable, Equatable {
        case none
        case needsCatchUp(ConversationID, after: UInt64)
    }

    /// Apply a live event from the per-user event stream. Returns a gap signal so the controller can
    /// trigger a `GetDelta` catch-up when the sequenced log skipped ahead.
    @discardableResult
    public mutating func apply(_ event: ConversationStreamEvent) -> GapSignal {
        switch event {
        case .newMessages(let conversationID, let messages):
            mergeMessages(messages, into: conversationID)
            if let latest = messages.max(by: { $0.id < $1.id }) {
                setLastMessage(latest, in: conversationID)
            }
            return .none
        case .chatEvents(let conversationID, let events):
            return applyChatEvents(events, into: conversationID)
        case .metadataRefresh(let conversation):
            upsert(conversation)
            return .none
        case .lastActivityChanged(let conversationID, let date):
            guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return .none }
            conversations[index].lastActivity = date
            sort()
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

    /// Apply sequenced event-log mutations in ascending order: merge each (last-writer-wins), advance
    /// the contiguous frontier while events arrive gapless, and flag a gap the moment one is skipped so
    /// the caller catches up via `GetDelta`. Only `.sent` mutations bump the feed's activity and
    /// re-sort — an edit/delete carries the message's original (low) id and must not move the row.
    private mutating func applyChatEvents(_ events: [DecodedChatEvent], into conversationID: ConversationID) -> GapSignal {
        var cursor = appliedCursorByConversation[conversationID] ?? 0
        var newestSent: ConversationMessage?
        var gapAfter: UInt64?
        var incoming: [ConversationMessage] = []

        for event in events.sorted(by: { $0.sequence < $1.sequence }) {
            incoming.append(contentsOf: event.mutations.map(\.message))
            for case .sent(let message) in event.mutations {
                if newestSent.map({ message.id > $0.id }) ?? true { newestSent = message }
            }

            // Gap-detect only once the frontier is established (a catch-up seeds it); before that, live
            // events are applied by LWW and the initial GetDelta owns the cursor.
            guard gapAfter == nil, cursor > 0 else { continue }
            if event.sequence <= cursor {
                continue // already applied — a duplicate/stale re-delivery, merged harmlessly
            }
            if event.sequence == cursor + event.count {
                cursor = event.sequence // contiguous — advance the frontier
            } else {
                gapAfter = cursor // hole below this event; stop advancing and catch up from here
            }
        }

        // One merge for the whole batch (LWW is order-independent, so a per-event merge only re-sorted
        // the full transcript K times); `mergeMessages` no-ops on an empty batch.
        mergeMessages(incoming, into: conversationID)
        appliedCursorByConversation[conversationID] = cursor
        if let newestSent {
            setLastMessage(newestSent, in: conversationID)
        }
        return gapAfter.map { .needsCatchUp(conversationID, after: $0) } ?? .none
    }

    // MARK: - Event-log catch-up cursor

    /// The frontier to pass as `GetDelta.after_sequence` for a conversation (zero = fetch from the
    /// beginning of the retained log).
    public func appliedCursor(for conversationID: ConversationID) -> UInt64 {
        appliedCursorByConversation[conversationID] ?? 0
    }

    /// Apply a `GetDelta` batch: merge its messages (last-writer-wins), then advance the frontier to
    /// the batch's checkpoint.
    public mutating func applyDeltaBatch(_ messages: [ConversationMessage], checkpoint: UInt64?, into conversationID: ConversationID) {
        mergeMessages(messages, into: conversationID) // no-ops on an empty batch
        if let checkpoint {
            setAppliedCursor(checkpoint, for: conversationID)
        }
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
