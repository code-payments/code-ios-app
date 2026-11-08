//
//  PendingReadPointer.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Observation
import FlipcashCore

/// The newest message the reader has had on screen on this visit, held back from the controller's
/// READ pointer until the reports stop for a beat.
///
/// Scrolling through unread rows reports a new message every few frames. Each pointer advance writes
/// the conversation to the database and mutates the store the whole screen observes, so advancing
/// per row hitches the scroll. The jump badge reads ``seenThrough`` instead and stays live.
@MainActor
@Observable
final class PendingReadPointer {

    /// The newest message reported on screen; runs ahead of the controller's pointer until committed.
    private(set) var seenThrough: MessageID?

    @ObservationIgnored private let controller: ConversationController
    @ObservationIgnored private let conversationID: ConversationID
    @ObservationIgnored private let delay: Duration
    @ObservationIgnored private var commitTask: Task<Void, Never>?

    init(controller: ConversationController, conversationID: ConversationID, delay: Duration = .milliseconds(500)) {
        self.controller = controller
        self.conversationID = conversationID
        self.delay = delay
    }

    /// Records `messageID` as seen, and commits it once no newer report has come in for the delay.
    func markSeen(_ messageID: MessageID) {
        if let seenThrough, messageID <= seenThrough { return }
        seenThrough = messageID
        commitTask?.cancel()
        commitTask = Task { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.commit()
        }
    }

    /// Advances the controller's READ pointer to everything seen so far, now.
    func commit() {
        commitTask?.cancel()
        commitTask = nil
        guard let seenThrough else { return }
        controller.advanceReadPointer(to: seenThrough, in: conversationID)
    }
}
