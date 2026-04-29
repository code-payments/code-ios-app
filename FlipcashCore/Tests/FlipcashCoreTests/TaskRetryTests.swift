import Foundation
import Testing
@testable import FlipcashCore

@Suite("Task.retry")
struct TaskRetryTests {

    private struct Stub: Error, Equatable {}
    private struct OtherError: Error {}

    @Test("Returns immediately when body succeeds on the first try")
    func succeedsFirstTry() async throws {
        var attempts = 0
        let result = try await Task.retry(maxAttempts: 3, delay: .nanoseconds(1)) {
            attempts += 1
            return 42
        }
        #expect(result == 42)
        #expect(attempts == 1)
    }

    @Test("Retries until body succeeds")
    func retriesUntilSuccess() async throws {
        var attempts = 0
        let result = try await Task.retry(maxAttempts: 3, delay: .nanoseconds(1)) {
            attempts += 1
            if attempts < 3 { throw Stub() }
            return 42
        }
        #expect(result == 42)
        #expect(attempts == 3)
    }

    @Test("Rethrows after maxAttempts is exhausted")
    func rethrowsAfterMaxAttempts() async {
        var attempts = 0
        await #expect(throws: Stub.self) {
            try await Task.retry(maxAttempts: 3, delay: .nanoseconds(1)) {
                attempts += 1
                throw Stub()
            }
        }
        #expect(attempts == 3)
    }

    @Test("Stops retrying when shouldRetry returns false")
    func stopsOnNonRetryable() async {
        var attempts = 0
        await #expect(throws: Stub.self) {
            try await Task.retry(
                maxAttempts: 5,
                delay: .nanoseconds(1),
                shouldRetry: { _ in false }
            ) {
                attempts += 1
                throw Stub()
            }
        }
        #expect(attempts == 1)
    }

    @Test("shouldRetry is called with the actual thrown error")
    func shouldRetryReceivesError() async {
        var seen: [Error] = []
        var attempts = 0
        await #expect(throws: OtherError.self) {
            try await Task.retry(
                maxAttempts: 3,
                delay: .nanoseconds(1),
                shouldRetry: { error in
                    seen.append(error)
                    return error is Stub
                }
            ) {
                attempts += 1
                if attempts < 2 { throw Stub() }
                throw OtherError()
            }
        }
        #expect(attempts == 2)
        #expect(seen.count == 2)
        #expect(seen[0] is Stub)
        #expect(seen[1] is OtherError)
    }

    @Test("maxAttempts of 1 disables retry — body runs once and rethrows")
    func maxAttemptsOneRunsOnce() async {
        var attempts = 0
        await #expect(throws: Stub.self) {
            try await Task.retry(maxAttempts: 1, delay: .nanoseconds(1)) {
                attempts += 1
                throw Stub()
            }
        }
        #expect(attempts == 1)
    }
}
