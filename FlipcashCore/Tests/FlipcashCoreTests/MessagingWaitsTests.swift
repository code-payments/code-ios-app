import Foundation
import Testing
@testable import FlipcashCore

@Suite("Messaging waits")
struct MessagingWaitsTests {

    private let testMint = try! PublicKey(base58: "54ggcQ23uen5b9QXMAns99MQNTKn7iyzq4wvCW6e8r25")
    private let testAccount = try! PublicKey(base58: "54ggcQ23uen5b9QXMAns99MQNTKn7iyzq4wvCW6e8r25")
    private let testSignature = try! Signature(Array(repeating: Byte(0), count: 64))

    private func messageID() -> ID {
        ID(data: Data([UInt8.random(in: 0...255)]))
    }

    private func paymentRequestMessage() -> StreamMessage {
        StreamMessage(
            id: messageID(),
            kind: .paymentRequest(
                PaymentRequest(account: testAccount, signature: testSignature)
            )
        )
    }

    private func giveRequestMessage() -> StreamMessage {
        StreamMessage(
            id: messageID(),
            kind: .requestToGiveBill(testMint, nil, nil)
        )
    }

    // MARK: - firstPaymentRequest -

    @Test("Returns first payment request and leaves the stream alone")
    func firstPaymentRequest_returnsMatch() async throws {
        let (stream, continuation) = AsyncThrowingStream<[StreamMessage], Error>.makeStream()

        let consumer = Task {
            try await firstPaymentRequest(in: stream, shouldIgnore: { false })
        }

        continuation.yield([paymentRequestMessage()])

        let request = try await consumer.value
        #expect(request.account == testAccount)
    }

    @Test("Skips batches while shouldIgnore is true, then returns on the next match")
    func firstPaymentRequest_respectsIgnore() async throws {
        let (stream, continuation) = AsyncThrowingStream<[StreamMessage], Error>.makeStream()
        let ignoreFlag = ToggleFlag(initial: true)

        let consumer = Task {
            try await firstPaymentRequest(in: stream, shouldIgnore: { ignoreFlag.value })
        }

        // First batch arrives while ignored — dropped.
        continuation.yield([paymentRequestMessage()])
        try await Task.sleep(for: .milliseconds(10))

        // Flip the flag and deliver another batch — consumer should take this one.
        ignoreFlag.set(false)
        continuation.yield([paymentRequestMessage()])

        let request = try await consumer.value
        #expect(request.account == testAccount)
    }

    @Test("Throws streamClosedBeforeRequest when the stream finishes without a match")
    func firstPaymentRequest_streamClosedEmpty() async throws {
        let (stream, continuation) = AsyncThrowingStream<[StreamMessage], Error>.makeStream()

        let consumer = Task {
            try await firstPaymentRequest(in: stream, shouldIgnore: { false })
        }

        continuation.finish()

        await #expect(throws: MessagingWaitError.streamClosedBeforeRequest) {
            _ = try await consumer.value
        }
    }

    // MARK: - pollForGiveRequest -

    @Test("Returns decoded GiveRequest from the first matching poll batch")
    func pollForGiveRequest_returnsMatch() async throws {
        let mint = testMint
        let request = try await pollForGiveRequest(
            maxAttempts: 3,
            pollInterval: .milliseconds(10),
            fetch: { [giveRequestMessage()] }
        )

        #expect(request.mint == mint)
        #expect(request.verifiedState == nil)
        #expect(request.mintMetadata == nil)
    }

    @Test("Skips empty batches and returns on the first non-empty batch that contains a match")
    func pollForGiveRequest_skipsEmptyBatches() async throws {
        let attemptLog = AttemptLog()
        let target = giveRequestMessage()

        let request = try await pollForGiveRequest(
            maxAttempts: 5,
            pollInterval: .milliseconds(5),
            fetch: {
                let n = attemptLog.incrementAndGet()
                return n < 3 ? [] : [target]
            }
        )

        #expect(request.mint == testMint)
        #expect(attemptLog.count == 3)
    }

    @Test("Times out after maxAttempts when no give-bill message ever appears")
    func pollForGiveRequest_timesOut() async throws {
        let attemptLog = AttemptLog()

        await #expect(throws: MessagingWaitError.timedOut) {
            _ = try await pollForGiveRequest(
                maxAttempts: 3,
                pollInterval: .milliseconds(5),
                fetch: {
                    _ = attemptLog.incrementAndGet()
                    return []
                }
            )
        }
        #expect(attemptLog.count == 3)
    }

    // MARK: - Test helper -

    private final class ToggleFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var flag: Bool
        init(initial: Bool) { self.flag = initial }
        var value: Bool {
            lock.lock(); defer { lock.unlock() }
            return flag
        }
        func set(_ newValue: Bool) {
            lock.lock(); defer { lock.unlock() }
            flag = newValue
        }
    }

    private final class AttemptLog: @unchecked Sendable {
        private let lock = NSLock()
        private var counter = 0
        var count: Int {
            lock.lock(); defer { lock.unlock() }
            return counter
        }
        func incrementAndGet() -> Int {
            lock.lock(); defer { lock.unlock() }
            counter += 1
            return counter
        }
    }
}
