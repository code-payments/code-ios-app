import Foundation
import Testing
import Combine
@testable import FlipcashCore

@Suite("asyncThrowingStream bridge")
struct AsyncStreamBridgeTests {

    @Test("Yields successive values to the consumer")
    func yieldsValues() async throws {
        let stream = asyncThrowingStream(from: { callback in
            callback(.success(1))
            callback(.success(2))
            callback(.success(3))
            return AnyCancellable { }
        }) as AsyncThrowingStream<Int, Error>

        var received: [Int] = []
        for try await value in stream {
            received.append(value)
            if received.count == 3 { break }
        }

        #expect(received == [1, 2, 3])
    }

    @Test("Consumer throws when subscription delivers an error")
    func propagatesFailure() async {
        struct BridgeError: Error, Equatable {}

        let stream = asyncThrowingStream(from: { callback in
            callback(.failure(BridgeError()))
            return AnyCancellable { }
        }) as AsyncThrowingStream<Int, Error>

        await #expect(throws: BridgeError.self) {
            for try await _ in stream {
                Issue.record("Expected throw before any yield")
            }
        }
    }

    @Test("Subscription is cancelled when consumer breaks out of the loop")
    func cancelsSubscriptionOnBreak() async throws {
        let cancelled = Cancelled()

        // Inline the stream so its only strong reference is the `for` loop's
        // iterator. Dropping to the outer scope releases the stream and fires
        // `onTermination`. Assigning to a `let` would keep it alive until the
        // function returns and break this test's timing.
        func consume() async throws {
            let stream: AsyncThrowingStream<Int, Error> = asyncThrowingStream { callback in
                callback(.success(42))
                return AnyCancellable { cancelled.set() }
            }
            for try await _ in stream {
                break
            }
        }
        try await consume()

        for _ in 0..<100 {
            if cancelled.value { break }
            try await Task.sleep(for: .milliseconds(1))
        }

        #expect(cancelled.value)
    }

    @Test("Subscription is cancelled when the outer Task is cancelled")
    func cancelsSubscriptionOnTaskCancel() async throws {
        let cancelled = Cancelled()

        let task = Task {
            let stream = asyncThrowingStream(from: { _ in
                AnyCancellable { cancelled.set() }
            }) as AsyncThrowingStream<Int, Error>

            for try await _ in stream { }
        }

        // Give the stream a moment to attach, then cancel the consumer.
        try await Task.sleep(for: .milliseconds(5))
        task.cancel()
        _ = try? await task.value

        for _ in 0..<100 {
            if cancelled.value { break }
            try await Task.sleep(for: .milliseconds(1))
        }

        #expect(cancelled.value)
    }

    private final class Cancelled: @unchecked Sendable {
        private let lock = NSLock()
        private var flag = false
        var value: Bool {
            lock.lock(); defer { lock.unlock() }
            return flag
        }
        func set() {
            lock.lock(); defer { lock.unlock() }
            flag = true
        }
    }
}
