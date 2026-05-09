//
//  StressTestSupport.swift
//  FlipcashTests
//

import Testing
import Foundation

/// Run a body in a Task that cancels after a brief warmup, so cancellation
/// can land mid-flight rather than before the runtime has scheduled the
/// first iteration. Returns once the task completes (or its cancellation
/// propagates through whatever its body awaits).
///
/// The warmup window is short enough that fast machines still observe at
/// least one iteration before cancel, and slow machines still serialize.
@Sendable
func runCancellationStress(
    iterations: Int = 1_000,
    warmup: Duration = .milliseconds(5),
    body: @escaping @Sendable () async -> Void
) async {
    let task = Task {
        for _ in 0..<iterations {
            if Task.isCancelled { break }
            await body()
        }
    }
    try? await Task.sleep(for: warmup)
    task.cancel()
    _ = await task.value
}

/// Throwing variant for bodies that can throw (e.g., gRPC helpers).
@Sendable
func runThrowingCancellationStress(
    iterations: Int = 1_000,
    warmup: Duration = .milliseconds(5),
    body: @escaping @Sendable () async throws -> Void
) async {
    let task = Task {
        for _ in 0..<iterations {
            try Task.checkCancellation()
            try await body()
        }
    }
    try? await Task.sleep(for: warmup)
    task.cancel()
    _ = try? await task.value
}
