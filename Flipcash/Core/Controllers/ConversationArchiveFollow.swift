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

    @ObservationIgnored private let streaming: any ConversationEventStreaming
    /// How long following stays on after the user leaves the archive. Covers a push from the
    /// Archived screen into a chat, which may clear one input before it sets the other.
    @ObservationIgnored private let grace: Duration
    /// What the stream was last asked for.
    @ObservationIgnored private var follows = false
    /// The sends, chained so they reach the stream in the order they were decided.
    @ObservationIgnored private var sendTask: Task<Void, Never>?
    /// The pending OFF, cancelled if the user comes back within `grace`.
    @ObservationIgnored private var offTask: Task<Void, Never>?

    /// Creates a follow that sends through `streaming` and stays on for `grace` after the user leaves.
    init(streaming: any ConversationEventStreaming, grace: Duration) {
        self.streaming = streaming
        self.grace = grace
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
        let previous = sendTask
        sendTask = Task { [streaming] in
            await previous?.value
            await streaming.setConversationStreamFollowsArchive(follow)
        }
    }
}
