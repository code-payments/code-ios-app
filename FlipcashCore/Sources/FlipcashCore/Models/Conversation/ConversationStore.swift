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

    /// Replace the feed from a paged load, sorted most-recent-activity first.
    public mutating func setFeed(_ conversations: [Conversation]) {
        self.conversations = conversations.sorted { $0.lastActivity > $1.lastActivity }
    }

    /// How far apart an incoming server copy and a pending optimistic send may be (in either
    /// direction, to absorb client/server clock skew) and still be treated as the same message. Wide
    /// enough for skew, tight enough that an unrelated old history message with identical text never
    /// reconciles a fresh pending send.
    private static let pendingReconcileWindow: TimeInterval = 5 * 60

    /// Insert/replace messages keyed by their gapless id, keeping oldest first. Reconciles a server
    /// copy of one of our own optimistic sends — which carries no client id, because the server never
    /// echoes it — against the matching pending row, so the echo collapses onto that row instead of
    /// duplicating it, no matter which path (stream, history load, or the send RPC) delivers it first.
    public mutating func mergeMessages(_ incoming: [ConversationMessage], into conversationID: ConversationID) {
        guard !incoming.isEmpty else { return }
        let current = messagesByConversation[conversationID] ?? []

        var byID = Dictionary(
            current.map { ($0.id, $0) },
            uniquingKeysWith: { _, new in new }
        )
        for message in incoming {
            var message = message
            // A server copy with no client id is either the echo of one of our optimistic sends or a
            // re-delivery of an already-known row. Only a brand-new id (not already confirmed) can be a
            // fresh send's echo, so only then do we content-match a pending row — this keeps a
            // re-delivery of an OLD identical message from stealing a fresh pending send. Adopting the
            // pending row's client id (and dropping that pending copy) keeps one stable identity across
            // sending → sent; for an already-known id we just keep the client id already on the row.
            if message.clientMessageID == nil {
                if byID[message.id] == nil, let clientMessageID = reconcilePendingMatch(for: message, in: conversationID) {
                    message.clientMessageID = clientMessageID
                } else if let existing = byID[message.id]?.clientMessageID {
                    message.clientMessageID = existing
                }
            }
            byID[message.id] = message
        }
        messagesByConversation[conversationID] = byID.values.sorted { $0.id < $1.id }
    }

    /// Removes and returns the client id of the oldest pending send that matches `serverCopy` by sender
    /// and content within the reconcile window — the optimistic row this server copy confirms. Returns
    /// nil when nothing matches (a counterpart message, or an unrelated history message).
    private mutating func reconcilePendingMatch(for serverCopy: ConversationMessage, in conversationID: ConversationID) -> UUID? {
        guard var pending = pendingByConversation[conversationID],
              let index = pending.firstIndex(where: {
                  $0.message.senderID == serverCopy.senderID
                      && $0.message.content == serverCopy.content
                      && abs($0.message.date.timeIntervalSince(serverCopy.date)) < Self.pendingReconcileWindow
              }) else {
            return nil
        }
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

    /// Bump a conversation's last message + activity and re-sort the feed.
    public mutating func setLastMessage(_ message: ConversationMessage, in conversationID: ConversationID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[index].lastMessage = message
        conversations[index].lastActivity = message.date
        sort()
    }

    /// Apply a live event from the per-user event stream.
    public mutating func apply(_ event: ConversationStreamEvent) {
        switch event {
        case .newMessages(let conversationID, let messages):
            mergeMessages(messages, into: conversationID)
            if let latest = messages.max(by: { $0.id < $1.id }) {
                setLastMessage(latest, in: conversationID)
            }
        case .metadataRefresh(let conversation):
            upsert(conversation)
        case .lastActivityChanged(let conversationID, let date):
            guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
            conversations[index].lastActivity = date
            sort()
        case .readPointersChanged(let conversationID, let pointers):
            for pointer in pointers {
                advanceReadPointer(to: pointer.value, for: pointer.userID, at: pointer.date, in: conversationID)
            }
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
