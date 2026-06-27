//
//  ReceiptSettleGate.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Holds a just-sent message's delivery receipt for a short beat after its bubble is inserted, so
/// "Delivered" cross-fades onto a settled row instead of popping in mid-insert. Owns the held id, the
/// timer, and the delay as one unit; the transcript mapping reads `settlingID` to suppress that row's
/// receipt while it's held.
///
/// Main-actor isolated (not an `actor`) because the state is UI-bound: the SwiftUI mapping reads
/// `settlingID` synchronously, which actor isolation would force behind `await`, and it's only ever
/// mutated on the main actor — there's no second concurrency domain to protect.
@MainActor @Observable
final class ReceiptSettleGate {

    /// The `stableID` of the row whose receipt is currently held back, or nil when nothing is settling.
    private(set) var settlingID: String?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let delay: Duration

    init(delay: Duration = .milliseconds(500)) {
        self.delay = delay
    }

    /// Begin holding `id`'s receipt; it clears on its own after the settle delay. A newer hold replaces
    /// the current one — only the latest send shows a receipt.
    func hold(_ id: String) {
        settlingID = id
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: self?.delay ?? .zero)
            guard !Task.isCancelled, self?.settlingID == id else { return }
            self?.settlingID = nil
        }
    }

    /// Stop holding and cancel the timer (e.g. when the conversation tears down).
    func cancel() {
        task?.cancel()
        task = nil
        settlingID = nil
    }
}
