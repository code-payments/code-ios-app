//
//  WaitForState.swift
//  FlipcashTests
//

import Foundation
import Testing

/// Polls an observable object's state until `predicate` returns true or the
/// timeout elapses. Used to coordinate async-continuation tests that pause
/// at known state transitions before driving the next input.
///
/// Polling (vs. `withObservationTracking`) keeps the helper simple at the
/// cost of a small fixed-interval sleep. Tests are short-lived; the cost is
/// negligible. Failure records a `Testing` issue at the call site and throws
/// `WaitForStateTimeout` so callers can fail fast.
@MainActor
func waitUntil<Object: AnyObject>(
    _ object: Object,
    timeout: Duration = .seconds(2),
    pollInterval: Duration = .milliseconds(5),
    sourceLocation: SourceLocation = #_sourceLocation,
    matches predicate: @MainActor (Object) -> Bool
) async throws {
    let deadline = ContinuousClock().now + timeout
    while !predicate(object) {
        if ContinuousClock().now >= deadline {
            Issue.record(
                "waitUntil(\(Object.self)) timed out after \(timeout)",
                sourceLocation: sourceLocation
            )
            throw WaitForStateTimeout()
        }
        try await Task.sleep(for: pollInterval)
    }
}

struct WaitForStateTimeout: Error {}
