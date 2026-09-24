//
//  ConversationTyping.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

nonisolated private let logger = Logger(label: "flipcash.conversation-controller")

/// The time source incoming typists are stamped and expired against.
nonisolated struct TypingExpiryClock: Sendable {
    /// Returns the current instant.
    let now: @Sendable () -> ContinuousClock.Instant
    /// Suspends until `deadline`, throwing if the task is cancelled first.
    let sleep: @Sendable (_ deadline: ContinuousClock.Instant) async throws -> Void

    /// Wall time, via `ContinuousClock`.
    static let continuous = TypingExpiryClock(
        now: { ContinuousClock.now },
        sleep: { try await Task.sleep(until: $0, clock: .continuous) }
    )
}

/// Typing indicators for conversations: broadcasts the signed-in user's typing state
/// and tracks which counterparts are typing. The server relays typing best-effort with
/// no timeout of its own, so stale typists are expired locally.
@MainActor
@Observable
final class ConversationTyping {

    @ObservationIgnored private let messaging: any ConversationMessaging
    @ObservationIgnored private let owner: KeyPair
    @ObservationIgnored private let selfUserID: UserID
    // 3s/5s cadence matches the Android client; injectable so tests can shorten them.
    private let heartbeatInterval: Duration
    private let timeout: Duration
    private let incomingExpiry: Duration
    @ObservationIgnored private let expiryClock: TypingExpiryClock

    /// OTHER members typing per conversation, each with when they started and their staleness deadline.
    private var typists: [ConversationID: [UserID: Typist]] = [:]
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    @ObservationIgnored private var isSelfTyping = false
    @ObservationIgnored private var selfTypingTask: Task<Void, Never>?
    @ObservationIgnored private var lastSentAt: ContinuousClock.Instant?
    /// At most one pending state per conversation; later states supersede in place.
    @ObservationIgnored private var pendingSends: [(conversationID: ConversationID, state: TypingState)] = []
    @ObservationIgnored private var sendTask: Task<Void, Never>?

    init(
        messaging: any ConversationMessaging,
        owner: KeyPair,
        selfUserID: UserID,
        heartbeatInterval: Duration = .seconds(3),
        timeout: Duration = .seconds(5),
        incomingExpiry: Duration = .seconds(10),
        expiryClock: TypingExpiryClock = .continuous
    ) {
        self.messaging = messaging
        self.owner = owner
        self.selfUserID = selfUserID
        self.heartbeatInterval = heartbeatInterval
        self.timeout = timeout
        self.incomingExpiry = incomingExpiry
        self.expiryClock = expiryClock
    }

    // MARK: - Incoming

    /// Returns whether another member is currently typing in the conversation.
    func isCounterpartTyping(in conversationID: ConversationID) -> Bool {
        !(typists[conversationID]?.isEmpty ?? true)
    }

    /// Returns the other members typing in the conversation, oldest to newest by when they started.
    func typists(in conversationID: ConversationID) -> [UserID] {
        guard let typists = typists[conversationID] else { return [] }
        // Ties on the start instant fall back to the id, so the order never flips between reads.
        return typists
            .sorted { ($0.value.startedAt, $0.key.uuidString) < ($1.value.startedAt, $1.key.uuidString) }
            .map(\.key)
    }

    /// Applies typing notifications from the live stream, ignoring the user's own.
    func apply(_ notifications: [TypingNotification], in conversationID: ConversationID) {
        for notification in notifications where notification.userID != selfUserID {
            switch notification.isActive {
            case true:
                let now = expiryClock.now()
                // A STILL heartbeat extends the deadline but keeps the typist's place in line.
                let startedAt = typists[conversationID]?[notification.userID]?.startedAt ?? now
                typists[conversationID, default: [:]][notification.userID] = Typist(
                    startedAt: startedAt,
                    deadline: now + incomingExpiry
                )
            case false:
                removeTypist(notification.userID, in: conversationID)
            }
        }
        scheduleExpirySweep()
    }

    private func removeTypist(_ userID: UserID, in conversationID: ConversationID) {
        typists[conversationID]?[userID] = nil
        if typists[conversationID]?.isEmpty == true {
            typists[conversationID] = nil
        }
    }

    /// One task, re-armed for the next-earliest deadline; ends when no typists remain.
    private func scheduleExpirySweep() {
        expiryTask?.cancel()
        expiryTask = nil
        guard let earliest = typists.values.flatMap(\.values).map(\.deadline).min() else { return }
        let expiryClock = expiryClock
        expiryTask = Task { [weak self] in
            try? await expiryClock.sleep(earliest)
            guard let self, !Task.isCancelled else { return }
            self.sweepExpiredTypists()
        }
    }

    private func sweepExpiredTypists() {
        let now = expiryClock.now()
        for (conversationID, members) in typists {
            for (userID, typist) in members where typist.deadline <= now {
                logger.debug("Expiring stale typist", metadata: [
                    "conversationID": "\(conversationID)",
                    "userID": "\(userID)",
                ])
                removeTypist(userID, in: conversationID)
            }
        }
        scheduleExpirySweep()
    }

    private struct Typist {
        var startedAt: ContinuousClock.Instant
        var deadline: ContinuousClock.Instant
    }

    // MARK: - Outgoing

    /// STARTED on first input, STILL at least every `heartbeatInterval` while typing
    /// continues, STOPPED after `timeout` idle or when the draft empties.
    func draftDidChange(_ text: String, in conversationID: ConversationID) {
        selfTypingTask?.cancel()
        guard !text.isEmpty else {
            stopSelfTyping(in: conversationID)
            return
        }
        selfTypingTask = Task { [weak self] in
            // Cancelled before running (fast type-then-clear): send nothing, or `isSelfTyping` wedges.
            guard let self, !Task.isCancelled else { return }
            if !self.isSelfTyping {
                self.isSelfTyping = true
                self.send(.started, in: conversationID)
            } else if let last = self.lastSentAt,
                      last.duration(to: ContinuousClock.now) >= self.heartbeatInterval {
                // The pause loop below restarts on every keystroke; this keeps heartbeats flowing.
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

    /// Stops broadcasting the user's typing state in the conversation.
    func stopSelfTyping(in conversationID: ConversationID) {
        selfTypingTask?.cancel()
        selfTypingTask = nil
        guard isSelfTyping else { return }
        isSelfTyping = false
        send(.stopped, in: conversationID)
    }

    /// Serialized so a STOPPED can never be overtaken by an in-flight STILL. Failures are
    /// best-effort chatter: logged (once per drain) and never reported to Bugsnag.
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
                }
            }
            // A cancelled drainer resuming late must not clear a successor's slot.
            if let self, !Task.isCancelled {
                self.sendTask = nil
            }
        }
    }

    // MARK: - Teardown

    /// Clears all typing state and cancels any in-flight work.
    func stop() {
        typists.removeAll()
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
