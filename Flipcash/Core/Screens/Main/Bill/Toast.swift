//
//  Toast.swift
//  Code
//
//  Created by Dima Bart on 2025-04-22.
//

import Foundation
import FlipcashCore

/// A FIFO queue that buffers ``Toast`` notifications for sequential display.
///
/// Toasts are inserted at the front and consumed from the back, so the oldest
/// toast is shown first. When a newly inserted toast *negates* the next one to
/// be shown (same amount, opposite direction), the older toast is removed to
/// avoid confusing back-to-back "+$X / -$X" flashes (e.g. a round-trip test
/// transaction).
struct ToastQueue {

    private var queue: [Toast] = []

    var hasToasts: Bool {
        !queue.isEmpty
    }

    init() {

    }

    /// Inserts a toast at the front of the queue.
    ///
    /// If the toast negates the next one to be consumed (same amount, opposite
    /// direction), the older toast is removed before the new one is inserted.
    mutating func insert(_ toast: Toast) {
        if let nextToast = queue.first, toast.negates(toast: nextToast) {
            queue.remove(at: 0)
        }
        queue.insert(toast, at: 0)
    }

    /// Removes and returns the oldest toast, or `nil` if the queue is empty.
    mutating func pop() -> Toast? {
        queue.popLast()
    }
}

/// A transient balance-change indicator shown briefly on the scan screen after
/// a cash transfer completes (give, grab, send link, or receive link).
///
/// Displayed as "+$X" for deposits or "-$X" for withdrawals. Consumption is
/// driven by ``Session``, which shows each toast for 3 seconds with a 1-second
/// gap between consecutive toasts, pausing while a bill is on screen.
struct Toast: Equatable, Hashable {

    /// The transaction amount.
    let amount: FiatAmount

    /// `true` when the user received funds, `false` when they sent funds.
    let isDeposit: Bool

    /// Returns `true` when this toast and `toast` represent equal amounts
    /// moving in opposite directions, effectively cancelling each other out.
    func negates(toast: Toast) -> Bool {
        self.amount == toast.amount &&
        self.isDeposit != toast.isDeposit
    }
}
