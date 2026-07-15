//
//  MessageLoader.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// A per-conversation, bounded window over a conversation's messages, read from the local database.
/// It renders only a recent slice so a fresh open lays out a window rather than the whole thread. The
/// window is anchored by message id once the reader pages back, so an arriving message grows it at the
/// tail instead of sliding the oldest revealed row out from under the reader; `loadOlder()` steps the
/// anchor over already-persisted history and pages the next older batch from the server (which
/// persists it) once local history is exhausted.
@MainActor @Observable
final class MessageLoader {

    private let conversationID: ConversationID
    private let controller: ConversationController

    /// The oldest revealed confirmed id; nil renders the newest `initialWindow`.
    private var startID: UInt64?
    /// `onReachTop` fires on every scroll tick near the top, so accept at most one growth step per
    /// interval — the async remap needs time to move the reader out of the trigger zone.
    @ObservationIgnored private var lastGrowth: ContinuousClock.Instant?
    private let growthInterval: Duration

    init(conversationID: ConversationID, controller: ConversationController, growthInterval: Duration = .milliseconds(300)) {
        self.conversationID = conversationID
        self.controller = controller
        self.growthInterval = growthInterval
    }

    /// The bounded slice actually rendered: the anchored window (or the newest `initialWindow`) from
    /// the DB with the optimistic overlay applied.
    var messages: [ConversationMessage] {
        controller.windowedMessages(for: conversationID, startingAt: startID, limit: Self.initialWindow)
    }

    /// Reveals an older step: moves the anchor back over already-persisted history, or pages the next
    /// older batch from the server (which persists it) once the local history is exhausted.
    func loadOlder() {
        let now = ContinuousClock.now
        if let lastGrowth, lastGrowth.duration(to: now) < growthInterval { return }
        lastGrowth = now

        guard let anchor = startID ?? controller.oldestWindowedMessageID(for: conversationID, limit: Self.initialWindow) else {
            fetchOlder()
            return
        }
        if let older = controller.olderAnchor(for: conversationID, before: anchor, step: Self.step) {
            startID = older
        } else {
            fetchOlder()
        }
    }

    private func fetchOlder() {
        Task {
            await controller.loadOlderMessages(for: conversationID)
            // Reveal the newly persisted page; no-ops when history was already exhausted.
            guard let anchor = startID ?? controller.oldestWindowedMessageID(for: conversationID, limit: Self.initialWindow),
                  let older = controller.olderAnchor(for: conversationID, before: anchor, step: Self.step) else { return }
            startID = older
        }
    }

    private static let initialWindow = 60
    private static let step = 40
}
