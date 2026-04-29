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
    /// The error from the final attempt is rethrown.
    ///
    /// - Parameters:
    ///   - maxAttempts: Total number of tries, including the first.
    ///     Must be at least 1.
    ///   - delay: Time to sleep between attempts.
    ///   - shouldRetry: Predicate over the thrown error. Defaults to
    ///     retrying every error. Return `false` to short-circuit.
    ///   - body: The async operation to attempt.
    public static func retry<T>(
        maxAttempts: Int,
        delay: Duration,
        shouldRetry: (Error) -> Bool = { _ in true },
        body: () async throws -> T
    ) async throws -> T {
        precondition(maxAttempts >= 1, "maxAttempts must be at least 1")
        var attempt = 0
        while true {
            attempt += 1
            do {
                return try await body()
            } catch {
                if attempt >= maxAttempts || !shouldRetry(error) {
                    throw error
                }
                try await Task.sleep(for: delay)
            }
        }
    }
}
