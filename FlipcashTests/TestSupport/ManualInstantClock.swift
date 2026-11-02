//
//  ManualInstantClock.swift
//  FlipcashTests
//

import Foundation

/// A monotonic clock that only moves when the test calls `advance(by:)`, for the
/// `now` seam of `AddMoneyTimer`.
final class ManualInstantClock: @unchecked Sendable {

    private let lock = NSLock()
    private var current = ContinuousClock.now

    /// The seam to hand the timer.
    var now: @Sendable () -> ContinuousClock.Instant {
        { [self] in lock.withLock { current } }
    }

    func advance(by duration: Duration) {
        lock.withLock { current += duration }
    }
}
