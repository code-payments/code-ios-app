//
//  ManualTypingClock.swift
//  FlipcashTests
//

import Foundation
@testable import Flipcash

/// A typing-expiry clock that only moves when the test calls `advance(by:)`, so a
/// typist lapses at a step the test chose rather than whenever the runner gets to it.
final class ManualTypingClock: @unchecked Sendable {

    private struct Sleeper {
        let id: UUID
        let deadline: ContinuousClock.Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let lock = NSLock()
    private let origin = ContinuousClock.now
    private var _now: ContinuousClock.Instant
    private var sleepers: [Sleeper] = []

    init() {
        _now = origin
    }

    /// The clock to hand the controller.
    var clock: TypingExpiryClock {
        TypingExpiryClock(
            now: { [self] in lock.withLock { _now } },
            sleep: { [self] deadline in try await sleep(until: deadline) }
        )
    }

    /// The earliest deadline a sleeper is parked on, measured from when the clock was
    /// created, or nil when none is.
    var nextDeadline: Duration? {
        lock.withLock { sleepers.map(\.deadline).min().map { origin.duration(to: $0) } }
    }

    /// Moves the clock forward and wakes every sleeper whose deadline it reached.
    func advance(by duration: Duration) {
        let due = lock.withLock {
            _now += duration
            let due = sleepers.filter { $0.deadline <= _now }
            sleepers.removeAll { $0.deadline <= _now }
            return due
        }
        for sleeper in due { sleeper.continuation.resume() }
    }

    private func sleep(until deadline: ContinuousClock.Instant) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let parked = lock.withLock { () -> Bool in
                    // A deadline the clock already passed returns at once, as a real sleep would.
                    guard deadline > _now, !Task.isCancelled else { return false }
                    sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    return true
                }
                if !parked {
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        continuation.resume()
                    }
                }
            }
        } onCancel: {
            let cancelled = lock.withLock { () -> Sleeper? in
                guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return nil }
                return sleepers.remove(at: index)
            }
            cancelled?.continuation.resume(throwing: CancellationError())
        }
    }
}
