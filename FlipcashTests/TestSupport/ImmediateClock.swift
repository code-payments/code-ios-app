//
//  ImmediateClock.swift
//  FlipcashTests
//

import Foundation

/// A clock whose `sleep` returns at once and moves `now` to the deadline, so a polling loop
/// covers its whole window in virtual time, however slowly the runner schedules the test.
final class ImmediateClock: Clock, @unchecked Sendable {

    struct Instant: InstantProtocol {
        fileprivate var offset: Duration

        func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    private let lock = NSLock()
    private var current = Instant(offset: .zero)

    var now: Instant {
        lock.withLock { current }
    }

    var minimumResolution: Duration { .zero }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try Task.checkCancellation()
        lock.withLock { current = max(current, deadline) }
    }
}
