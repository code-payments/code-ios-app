//
//  ToastController.swift
//  Flipcash
//

import Foundation
import FlipcashCore

private let logger = Logger(label: "flipcash.toasts")

/// Buffers and sequentially displays balance-change ``Toast`` notifications.
///
/// Cash flows enqueue toasts as transfers settle; consumption pauses while a
/// bill is on screen (`isSuppressed`) and resumes when the bill is dismissed.
@Observable
final class ToastController {

    /// The currently visible balance-change toast, or `nil` when none is shown.
    /// Set by ``consume()`` and cleared after a 3-second display window.
    var toast: Toast? = nil

    /// Live predicate that defers consumption while a bill is on screen.
    /// Wired by `Session.init` to `isShowingBill`.
    @ObservationIgnored var isSuppressed: () -> Bool = { false }

    @ObservationIgnored private var queue = ToastQueue()

    /// Adds a toast to the queue without triggering consumption.
    ///
    /// Consumption is triggered externally (e.g. after a bill is dismissed
    /// via `Session.Cash.dismissBill`).
    func enqueue(_ toast: Toast) {
        queue.insert(toast)
    }

    /// Pops the next toast from the queue and displays it for 3 seconds.
    ///
    /// Consumption is deferred while `isSuppressed()` is `true` — the bill
    /// dismissal path calls this method again so queued toasts resume.
    /// After each toast, a 1-second gap separates consecutive notifications.
    func consume() {
        guard queue.hasToasts else {
            return
        }

        Task {
            // Wait for bill animation to finish
            // before showing the toast
            try await Task.delay(milliseconds: 500)

            // Ensure that there's no bills showing
            // otherwise we'll wait for the dismissal
            // path to consume the toast
            guard !isSuppressed() else {
                logger.debug("Bill showing, waiting for toasts to resume...")
                return
            }

            guard queue.hasToasts else {
                return
            }

            toast = queue.pop()

            try await Task.delay(seconds: 3)
            toast = nil

            if queue.hasToasts {
                try await Task.delay(milliseconds: 1000)
                consume()
            }
        }
    }
}
