//
//  PushControllerDeadlineTests.swift
//  FlipcashTests
//

import Foundation
import os
import Testing
@testable import Flipcash

@Suite("PushController.withDeadline")
struct PushControllerDeadlineTests {

    @Test("Throws at the deadline even when the operation ignores cancellation")
    func throwsAtDeadlineWithoutAwaitingOperation() async {
        let operation = HeldOperation()

        await #expect(throws: CancellationError.self) {
            try await PushController.withDeadline(.now + .milliseconds(100)) {
                await operation.run()
            }
        }

        #expect(!operation.hasReturned)
        operation.release()
    }

    @Test("Returns the operation's value when it finishes before the deadline")
    func returnsValueBeforeDeadline() async throws {
        let value = try await PushController.withDeadline(.now + .seconds(5)) { 42 }
        #expect(value == 42)
    }

    @Test("Passes the operation's error through")
    func passesErrorThrough() async {
        struct Failure: Error {}
        await #expect(throws: Failure.self) {
            try await PushController.withDeadline(.now + .seconds(5)) { () async throws -> Int in
                throw Failure()
            }
        }
    }

    @Test("Throws as soon as the caller is cancelled, even when the operation ignores it")
    func throwsOnCallerCancellation() async {
        let operation = HeldOperation()
        let call = Task {
            try await PushController.withDeadline(.now + .seconds(5)) {
                await operation.run()
            }
        }
        try? await Task.sleep(for: .milliseconds(50))
        call.cancel()

        await #expect(throws: CancellationError.self) { try await call.value }
        #expect(!operation.hasReturned)
        operation.release()
    }

    // MARK: - Support -

    /// A stand-in for a send behind a continuation: it ignores cancellation and returns only once
    /// released.
    ///
    /// The test releases it after `withDeadline` has thrown, so the throw reaching the test while
    /// `hasReturned` is still false is what shows `withDeadline` didn't wait for it. Asserting on
    /// order instead of elapsed time keeps the check valid when a loaded runner stalls the process
    /// for tens of seconds. If `withDeadline` did wait, the backstop releases it so the test fails
    /// instead of hanging.
    private final class HeldOperation: Sendable {

        private struct State {
            var continuation: CheckedContinuation<Void, Never>?
            var isReleased = false
            var hasReturned = false
        }

        private static let backstop: Double = 120

        private let state = OSAllocatedUnfairLock(initialState: State())

        /// Whether `run()` has returned.
        var hasReturned: Bool { state.withLock { $0.hasReturned } }

        /// Suspends until `release()` is called or the backstop passes, ignoring cancellation.
        func run() async -> Int {
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.backstop) { [self] in release() }
            await withCheckedContinuation { continuation in
                let released = state.withLock { state in
                    if !state.isReleased { state.continuation = continuation }
                    return state.isReleased
                }
                if released { continuation.resume() }
            }
            state.withLock { $0.hasReturned = true }
            return 1
        }

        /// Lets `run()` return; later calls do nothing.
        func release() {
            let continuation = state.withLock { state -> CheckedContinuation<Void, Never>? in
                state.isReleased = true
                defer { state.continuation = nil }
                return state.continuation
            }
            continuation?.resume()
        }
    }
}
