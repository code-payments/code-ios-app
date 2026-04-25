//
//  PingTracker.swift
//  FlipcashCore
//

import Foundation

struct PingTracker {

    var lastPing: Date?
    var timeoutSeconds: Int = 15

    /// Records a ping and returns the current timeout. When the server provides
    /// `updatedTimeout`, it is doubled before being stored — the stream is given
    /// twice the server-requested window before the next ping is treated as missed.
    @discardableResult
    mutating func receivedPing(updatedTimeout: Int? = nil) -> Int {
        lastPing = .now

        if let updatedTimeout {
            let newTimeout = updatedTimeout * 2
            if timeoutSeconds != newTimeout {
                timeoutSeconds = newTimeout
            }
        }

        return timeoutSeconds
    }

    /// Wall-clock liveness check — `Task.sleep` does not fire promptly when the
    /// app resumes from suspension, so timer firing alone is not enough.
    var hasRecentPing: Bool {
        guard let lastPing else { return false }
        return Date.now.timeIntervalSince(lastPing) < TimeInterval(timeoutSeconds)
    }
}
