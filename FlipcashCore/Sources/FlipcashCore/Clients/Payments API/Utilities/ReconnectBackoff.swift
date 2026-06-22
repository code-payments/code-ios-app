//
//  ReconnectBackoff.swift
//  FlipcashCore
//

import Foundation

/// Returns an exponentially growing reconnect delay, capped at `maxDelay`, that
/// increases with each consecutive failure.
///
/// Call `reset()` only once the connection proves healthy (a received ping) —
/// resetting on stream open pins the delay at `baseDelay` and defeats the backoff.
struct ReconnectBackoff {

    private static let baseDelay: TimeInterval = 1
    private static let maxDelay: TimeInterval = 30

    private(set) var attempts = 0

    /// Records a failed attempt and returns how long to wait before retrying.
    mutating func next() -> TimeInterval {
        attempts += 1
        return min(Self.baseDelay * pow(2, Double(attempts - 1)), Self.maxDelay)
    }

    /// Clears the failure count after the connection proves healthy.
    mutating func reset() {
        attempts = 0
    }
}
