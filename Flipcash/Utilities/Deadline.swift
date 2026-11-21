//
//  Deadline.swift
//  Flipcash
//

import Foundation
import os

/// Runs `operation`, throwing `CancellationError` at `deadline` or when the caller is
/// cancelled, even if `operation` ignores cancellation.
nonisolated func withDeadline<T: Sendable>(
    _ deadline: ContinuousClock.Instant,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    // A task group would wait for an operation that ignores cancellation, so the result is
    // raced through one continuation and the loser is cancelled and left behind.
    let race = DeadlineRace<T>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            race.start(continuation, deadline: deadline, operation: operation)
        }
    } onCancel: {
        race.finish(.failure(CancellationError()))
    }
}

// MARK: - DeadlineRace -

/// Resumes one continuation with whichever of an operation, its deadline or the caller's
/// cancellation finishes first, then cancels the rest.
private nonisolated final class DeadlineRace<T: Sendable>: Sendable {

    private struct State {
        var continuation: CheckedContinuation<T, any Error>?
        var result: Result<T, any Error>?
        var tasks: [Task<Void, Never>] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func start(
        _ continuation: CheckedContinuation<T, any Error>,
        deadline: ContinuousClock.Instant,
        operation: @escaping @Sendable () async throws -> T
    ) {
        // The caller may already be cancelled, in which case `finish` ran first.
        let early = state.withLock { state in
            if state.result == nil { state.continuation = continuation }
            return state.result
        }
        if let early {
            continuation.resume(with: early)
            return
        }

        let work = Task {
            do {
                finish(.success(try await operation()))
            } catch {
                finish(.failure(error))
            }
        }
        let timer = Task {
            try? await Task.sleep(until: deadline, clock: .continuous)
            finish(.failure(CancellationError()))
        }
        let isFinished = state.withLock { state in
            if state.result == nil { state.tasks = [work, timer] }
            return state.result != nil
        }
        if isFinished {
            work.cancel()
            timer.cancel()
        }
    }

    /// Settles the race with `result` if it has not settled yet.
    func finish(_ result: Result<T, any Error>) {
        let winner = state.withLock { state -> (CheckedContinuation<T, any Error>?, [Task<Void, Never>])? in
            guard state.result == nil else { return nil }
            state.result = result
            defer {
                state.continuation = nil
                state.tasks = []
            }
            return (state.continuation, state.tasks)
        }
        guard let (continuation, tasks) = winner else { return }
        tasks.forEach { $0.cancel() }
        continuation?.resume(with: result)
    }
}
