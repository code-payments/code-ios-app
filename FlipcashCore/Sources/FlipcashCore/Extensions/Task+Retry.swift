//
//  Task+Retry.swift
//  FlipcashCore
//
//  Created by Raul Riera on 2026-04-29.
//

import Foundation

extension Task where Success == Never, Failure == Never {

    /// Runs `body`, retrying up to `maxAttempts - 1` times if the thrown
    /// error satisfies `shouldRetry`. Sleeps `delay` between attempts.
    /// The error from the final attempt is rethrown. `CancellationError` is
    /// never retried — it rethrows immediately so cancellation propagates
    /// promptly, regardless of `shouldRetry`.
    ///
    /// - Parameters:
    ///   - maxAttempts: Total number of tries, including the first.
    ///     Must be at least 1.
    ///   - delay: Time to sleep between attempts.
    ///   - shouldRetry: Predicate over the thrown error (never consulted for
    ///     `CancellationError`). Defaults to retrying every other error.
    ///     Return `false` to short-circuit.
    ///   - body: The async operation to attempt.
    public static func retry<T>(
        maxAttempts: Int,
        delay: Duration,
        shouldRetry: sending (Error) -> Bool = { _ in true },
        body: sending () async throws -> T
    ) async throws -> T {
        precondition(maxAttempts >= 1, "maxAttempts must be at least 1")
        var attempt = 0
        while true {
            attempt += 1
            do {
                return try await body()
            } catch {
                if error is CancellationError { throw error }
                if attempt >= maxAttempts || !shouldRetry(error) {
                    throw error
                }
                try await Task.sleep(for: delay)
            }
        }
    }

    /// Runs `operation` up to `maxAttempts` times, stopping the moment it returns
    /// `true`, sleeping `delay` between attempts. Returns `true` once it did, or
    /// `false` if every attempt returned `false`. Stops promptly on cancellation,
    /// returning `false`.
    ///
    /// Where `retry(maxAttempts:delay:…)` repeats on a thrown *error*, this repeats
    /// on an unsatisfied *result* — for polling a value that becomes available after
    /// a short delay (e.g. a record not yet queryable the instant it is created).
    ///
    /// - Parameters:
    ///   - maxAttempts: Total number of tries, including the first. Must be at least 1.
    ///   - delay: Time to sleep between attempts.
    ///   - operation: The async work to run each attempt; return `true` to stop.
    @discardableResult
    public static func retryUntil(
        maxAttempts: Int,
        delay: Duration,
        operation: sending () async -> Bool
    ) async -> Bool {
        precondition(maxAttempts >= 1, "maxAttempts must be at least 1")
        for attempt in 0..<maxAttempts {
            if attempt > 0 {
                try? await Task.sleep(for: delay)
                if Task.isCancelled { return false }
            }
            if await operation() { return true }
        }
        return false
    }
}
