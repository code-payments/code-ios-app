//
//  ApplePayIdleTimer.swift
//  Flipcash
//

import Foundation

/// One-shot timer that fires on `MainActor` if not disarmed before `timeout`
/// elapses. Used by `OnrampCoordinator` to dismiss the native Apple Pay sheet
/// when the user leaves it idle on screen. Mirrors the Android client's
/// `PAYMENT_SHEET_TIMEOUT_MS` (60s).
@MainActor
final class ApplePayIdleTimer {

    private let timeout: Duration

    private var task: Task<Void, Never>?

    init(timeout: Duration) {
        self.timeout = timeout
    }

    /// Arms (or re-arms) the timer. If a previous `arm` was pending, it is
    /// cancelled in favor of this one. `onExpiry` runs on `MainActor`.
    func arm(onExpiry: @escaping @MainActor () -> Void) {
        let timeout = self.timeout
        task?.cancel()
        task = Task { @MainActor in
            try? await Task.sleep(for: timeout)
            // `try?` above swallows the CancellationError from `disarm`; re-check before firing.
            guard !Task.isCancelled else { return }
            onExpiry()
        }
    }

    func disarm() {
        task?.cancel()
        task = nil
    }
}
