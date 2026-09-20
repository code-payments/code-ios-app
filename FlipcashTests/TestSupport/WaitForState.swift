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
///
/// The deadline is wall time, so it has to hold on CI's shared runner, where
/// parallel simulator clones stretch work that is instant on a dev machine
/// into tens of seconds. It only bounds how long a *failing* wait takes.
@MainActor
func waitUntil<Object: AnyObject>(
    _ object: Object,
    timeout: Duration = .seconds(30),
    pollInterval: Duration = .milliseconds(5),
    sourceLocation: SourceLocation = #_sourceLocation,
    matches predicate: @MainActor (Object) -> Bool
) async throws {
    let deadline = ContinuousClock().now + timeout
    while !predicate(object) {
        if ContinuousClock().now >= deadline {
            // `String(reflecting:)` dumps the object's stored properties so
            // a timeout reveals which state the predicate last rejected
            // instead of just the type name.
            Issue.record(
                "waitUntil(\(Object.self)) timed out after \(timeout). Last observed: \(String(reflecting: object))",
                sourceLocation: sourceLocation
            )
            throw WaitForStateTimeout()
        }
        try await Task.sleep(for: pollInterval)
    }
}

/// Polls `predicate` until it holds or the timeout elapses, for state that no
/// object reference reaches — a file a debounced write puts on disk, say.
///
/// Use this instead of sleeping past the interval you are waiting on. A fixed
/// sleep encodes an assumption about how promptly the work gets scheduled, and
/// that assumption is what fails on CI's shared runner: a 300 ms debounce can
/// land well after 900 ms of wall time there while landing in 5 ms locally.
@MainActor
func waitUntil(
    timeout: Duration = .seconds(30),
    pollInterval: Duration = .milliseconds(5),
    sourceLocation: SourceLocation = #_sourceLocation,
    _ predicate: @MainActor () throws -> Bool
) async throws {
    let deadline = ContinuousClock().now + timeout
    while try !predicate() {
        if ContinuousClock().now >= deadline {
            Issue.record(
                "waitUntil timed out after \(timeout).",
                sourceLocation: sourceLocation
            )
            throw WaitForStateTimeout()
        }
        try await Task.sleep(for: pollInterval)
    }
}

struct WaitForStateTimeout: Error {}
