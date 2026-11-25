//
//  ConversationArchiveFollow.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// Decides when the event stream follows archived groups: on while the Archived screen or an
/// archived group's chat is on screen, off once neither has been for the grace period.
@MainActor
@Observable
final class ConversationArchiveFollow {

    /// Whether the Archived screen is on screen.
    @ObservationIgnored var isArchiveScreenVisible = false {
        didSet { update() }
    }

    /// Whether the chat on screen is an archived group.
    @ObservationIgnored var isArchivedGroupVisible = false {
        didSet { update() }
    }

    /// Called when a follow goes `ackTimeout` without an ack, so archived groups are read anyway.
    @ObservationIgnored var onUnanswered: (() -> Void)?

    @ObservationIgnored private let streaming: any ConversationEventStreaming
    /// How long following stays on after the user leaves the archive. Covers a push from the
    /// Archived screen into a chat, which may clear one input before it sets the other.
    @ObservationIgnored private let grace: Duration
    /// How long a follow waits on its ack. A server without `FollowArchive` never sends one.
    @ObservationIgnored private let ackTimeout: Duration
    /// What the stream was last asked for.
    @ObservationIgnored private var follows = false
    /// The sends, chained so they reach the stream in the order they were decided.
    @ObservationIgnored private var sendTask: Task<Void, Never>?
    /// The pending OFF, cancelled if the user comes back within `grace`.
    @ObservationIgnored private var offTask: Task<Void, Never>?
    /// The wait on the current follow's ack, cancelled by the ack or by turning following off.
    @ObservationIgnored private var ackTask: Task<Void, Never>?

    /// Creates a follow that sends through `streaming`, stays on for `grace` after the user leaves,
    /// and calls ``onUnanswered`` when a follow goes `ackTimeout` without an ack.
    init(streaming: any ConversationEventStreaming, grace: Duration, ackTimeout: Duration) {
        self.streaming = streaming
        self.grace = grace
        self.ackTimeout = ackTimeout
    }

    /// Records the stream's ack of a follow, which stands down the unanswered fallback.
    func noteFollowAcknowledged() {
        ackTask?.cancel()
        ackTask = nil
    }

    private var wantsFollow: Bool {
        isArchiveScreenVisible || isArchivedGroupVisible
    }

    private func update() {
        guard wantsFollow else {
            guard follows, offTask == nil else { return }
            offTask = Task { [weak self, grace] in
                try? await Task.sleep(for: grace)
                guard let self, !Task.isCancelled else { return }
                self.offTask = nil
                if !self.wantsFollow {
                    self.send(false)
                }
            }
            return
        }
        offTask?.cancel()
        offTask = nil
        send(true)
    }

    private func send(_ follow: Bool) {
        guard follows != follow else { return }
        follows = follow
        ackTask?.cancel()
        ackTask = nil
        if follow {
            // Armed before the send is queued: its ack can be handled before the send returns.
            ackTask = Task { [weak self, ackTimeout] in
                try? await Task.sleep(for: ackTimeout)
                guard let self, !Task.isCancelled else { return }
                self.ackTask = nil
                self.onUnanswered?()
            }
        }
        let previous = sendTask
        sendTask = Task { [streaming] in
            await previous?.value
            await streaming.setConversationStreamFollowsArchive(follow)
        }
    }
}
