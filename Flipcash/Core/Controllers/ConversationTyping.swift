//
//  ConversationTyping.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

nonisolated private let logger = Logger(label: "flipcash.conversation-controller")

/// Owns the typing-indicator concern for DM conversations, both directions.
///
/// **Outgoing** — drives the signed-in user's typing state from the composer's draft:
/// STARTED on the first non-empty change, STILL at least every `heartbeatInterval`
/// while typing continues, STOPPED at `timeout` idle or when the draft empties.
/// Sends are serialized and coalesced per conversation so a STOPPED can never be
/// overtaken by an in-flight STILL.
///
/// **Incoming** — tracks which OTHER members are typing per conversation, expiring
/// each typist `incomingExpiry` after their last STARTED/STILL: the server is a
/// stateless relay with no timeout of its own, so a dropped STOPPED would otherwise
/// stick the indicator forever.
@MainActor
@Observable
final class ConversationTyping {

    @ObservationIgnored private let messaging: any ConversationMessaging
    @ObservationIgnored private let owner: KeyPair
    @ObservationIgnored private let selfUserID: UserID
    /// Cadence constants match the Android client so all clients agree; injected so
    /// tests can shorten them.
    private let heartbeatInterval: Duration
    private let timeout: Duration
    private let incomingExpiry: Duration

    // MARK: - Incoming state

    /// Per-conversation set of OTHER members currently typing, maintained from the live
    /// stream. Ephemeral — never persisted (the proto marks typing transient/best-effort).
    /// `Set<UserID>` is Equatable, so the @Observable setter skips no-op re-inserts.
    private var typingUserIDs: [ConversationID: Set<UserID>] = [:]
    /// Per-typist staleness deadlines backing `typingUserIDs`, swept by `expiryTask`.
    @ObservationIgnored private var expiries: [ConversationID: [UserID: ContinuousClock.Instant]] = [:]
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    // MARK: - Outgoing state

    @ObservationIgnored private var isSelfTyping = false
    @ObservationIgnored private var selfTypingTask: Task<Void, Never>?
    /// When the last outgoing state was queued; lets a keystroke emit the STILL heartbeat
    /// once `heartbeatInterval` has passed even while the pause loop keeps restarting.
    @ObservationIgnored private var lastSentAt: ContinuousClock.Instant?
    /// Outgoing states not yet on the wire, drained one at a time by `sendTask` so a
    /// STOPPED can never overtake an in-flight STILL. States are absolute, so each
    /// conversation holds at most one pending entry — later states supersede it in place.
    @ObservationIgnored private var pendingSends: [(conversationID: ConversationID, state: TypingState)] = []
    @ObservationIgnored private var sendTask: Task<Void, Never>?

    init(
        messaging: any ConversationMessaging,
        owner: KeyPair,
        selfUserID: UserID,
        heartbeatInterval: Duration = .seconds(3),
        timeout: Duration = .seconds(5),
        incomingExpiry: Duration = .seconds(10)
    ) {
        self.messaging = messaging
        self.owner = owner
        self.selfUserID = selfUserID
        self.heartbeatInterval = heartbeatInterval
        self.timeout = timeout
        self.incomingExpiry = incomingExpiry
    }

    // MARK: - Incoming

    /// Whether any OTHER member is currently typing in this conversation.
    func isCounterpartTyping(in conversationID: ConversationID) -> Bool {
        !(typingUserIDs[conversationID]?.isEmpty ?? true)
    }

    /// Applies a batch of typing notifications from the live stream. Self is excluded —
    /// the server may echo our own typing and we never show ourselves typing. Every
    /// STARTED/STILL refreshes the typist's staleness deadline.
    func apply(_ notifications: [TypingNotification], in conversationID: ConversationID) {
        for notification in notifications where notification.userID != selfUserID {
            switch notification.isActive {
            case true:
                typingUserIDs[conversationID, default: []].insert(notification.userID)
                expiries[conversationID, default: [:]][notification.userID] = ContinuousClock.now + incomingExpiry
            case false:
                removeTypist(notification.userID, in: conversationID)
            }
        }
        scheduleExpirySweep()
    }

    private func removeTypist(_ userID: UserID, in conversationID: ConversationID) {
        typingUserIDs[conversationID]?.remove(userID)
        if typingUserIDs[conversationID]?.isEmpty == true {
            typingUserIDs[conversationID] = nil
        }
        expiries[conversationID]?[userID] = nil
        if expiries[conversationID]?.isEmpty == true {
            expiries[conversationID] = nil
        }
    }

    /// (Re)arms the sweep for the earliest staleness deadline. One task at a time; each
    /// sweep re-arms for whatever deadline is next, and the task ends when no typists remain.
    private func scheduleExpirySweep() {
        expiryTask?.cancel()
        expiryTask = nil
        guard let earliest = expiries.values.flatMap(\.values).min() else { return }
        expiryTask = Task { [weak self] in
            try? await Task.sleep(until: earliest, clock: .continuous)
            guard let self, !Task.isCancelled else { return }
            self.sweepExpiredTypists()
        }
    }

    private func sweepExpiredTypists() {
        let now = ContinuousClock.now
        for (conversationID, deadlines) in expiries {
            for (userID, deadline) in deadlines where deadline <= now {
                logger.debug("Expiring stale typist", metadata: [
                    "conversationID": "\(conversationID)",
                    "userID": "\(userID)",
                ])
                removeTypist(userID, in: conversationID)
            }
        }
        scheduleExpirySweep()
    }

    // MARK: - Outgoing

    /// Drives outgoing typing from the composer's draft. Each change replaces the previous
    /// run, mirroring Android's `transformLatest` driver.
    func draftDidChange(_ text: String, in conversationID: ConversationID) {
        selfTypingTask?.cancel()
        guard !text.isEmpty else {
            stopSelfTyping(in: conversationID)
            return
        }
        selfTypingTask = Task { [weak self] in
            // A task cancelled before its body runs (a fast type-then-clear) must send nothing — otherwise
            // it would emit a STARTED with no matching STOPPED and wedge `isSelfTyping`.
            guard let self, !Task.isCancelled else { return }
            if !self.isSelfTyping {
                self.isSelfTyping = true
                self.send(.started, in: conversationID)
            } else if let last = self.lastSentAt,
                      last.duration(to: ContinuousClock.now) >= self.heartbeatInterval {
                // The pause loop below restarts on every keystroke, so continuous typing would
                // otherwise go silent after STARTED — and receivers expire stale typists.
                self.send(.still, in: conversationID)
            }
            var elapsed: Duration = .zero
            while elapsed < self.timeout {
                let wait = min(self.heartbeatInterval, self.timeout - elapsed)
                try? await Task.sleep(for: wait)
                if Task.isCancelled { return }
                elapsed += wait
                if elapsed < self.timeout {
                    self.send(.still, in: conversationID)
                }
            }
            self.isSelfTyping = false
            self.send(.stopped, in: conversationID)
        }
    }

    /// Force-stop outgoing typing (draft cleared, message sent, or the composer lost focus).
    func stopSelfTyping(in conversationID: ConversationID) {
        selfTypingTask?.cancel()
        selfTypingTask = nil
        guard isSelfTyping else { return }
        isSelfTyping = false
        send(.stopped, in: conversationID)
    }

    /// Queues a typing state and drains the queue one RPC at a time. Only the first failure
    /// per drain logs (an offline typing session would otherwise flood the export every few
    /// seconds); every failure still routes through `captureError`, which classifies
    /// transient ones as `.suppressed`.
    private func send(_ state: TypingState, in conversationID: ConversationID) {
        logger.debug("Queued typing notification", metadata: [
            "state": "\(state)",
            "conversationID": "\(conversationID)",
        ])
        lastSentAt = ContinuousClock.now
        if let index = pendingSends.firstIndex(where: { $0.conversationID == conversationID }) {
            pendingSends[index].state = state
        } else {
            pendingSends.append((conversationID: conversationID, state: state))
        }
        guard sendTask == nil else { return }
        sendTask = Task { [weak self] in
            var loggedFailure = false
            while let self, !Task.isCancelled, !self.pendingSends.isEmpty {
                let next = self.pendingSends.removeFirst()
                do {
                    try await self.messaging.notifyIsTyping(owner: self.owner, conversationID: next.conversationID, state: next.state)
                } catch {
                    if !loggedFailure {
                        loggedFailure = true
                        logger.warning("Typing notification failed", metadata: [
                            "state": "\(next.state)",
                            "error": "\(error)",
                        ])
                    }
                    ErrorReporting.captureError(error, reason: "Failed to notify typing")
                }
            }
            // `stop()` is the only other place that clears the slot, and it also cancels — so a
            // cancelled drainer resuming late must not clear what may be a successor's slot.
            if let self, !Task.isCancelled {
                self.sendTask = nil
            }
        }
    }

    // MARK: - Teardown

    /// Clears all typing state and cancels the driver, drainer, and expiry sweep.
    func stop() {
        typingUserIDs.removeAll()
        expiries.removeAll()
        expiryTask?.cancel()
        expiryTask = nil
        selfTypingTask?.cancel()
        selfTypingTask = nil
        isSelfTyping = false
        pendingSends.removeAll()
        sendTask?.cancel()
        sendTask = nil
    }
}
