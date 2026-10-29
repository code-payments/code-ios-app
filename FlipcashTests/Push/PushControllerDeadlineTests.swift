//
//  PushControllerDeadlineTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import Flipcash

@Suite("PushController.withDeadline")
struct PushControllerDeadlineTests {

    @Test("Throws at the deadline even when the operation ignores cancellation")
    func throwsAtDeadlineWithoutAwaitingOperation() async {
        let clock = ContinuousClock()
        let start = clock.now

        await #expect(throws: CancellationError.self) {
            try await PushController.withDeadline(start + .milliseconds(100)) {
                // Stands in for a request that only returns at its own, longer deadline.
                await Self.sleepIgnoringCancellation(seconds: 2)
                return 1
            }
        }

        #expect(clock.now - start < .milliseconds(600))
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
        let clock = ContinuousClock()
        let start = clock.now
        let call = Task {
            try await PushController.withDeadline(start + .seconds(5)) {
                await Self.sleepIgnoringCancellation(seconds: 2)
                return 1
            }
        }
        try? await Task.sleep(for: .milliseconds(50))
        call.cancel()

        await #expect(throws: CancellationError.self) { try await call.value }
        #expect(clock.now - start < .milliseconds(600))
    }

    // MARK: - Support -

    /// Suspends for `seconds` without responding to cancellation, like a send behind a continuation.
    private static func sleepIgnoringCancellation(seconds: Double) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                continuation.resume()
            }
        }
    }
}
