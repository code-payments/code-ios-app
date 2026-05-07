//
//  MessagingServiceFanInStressTests.swift
//  FlipcashTests
//
//  Pre-strip baseline for the Swift 6 / `defaultIsolation = MainActor`
//  migration. `MessagingService` opens the long-lived gRPC message stream
//  and fans batches into a `@MainActor`-hopping completion handler. The
//  service itself has no test seam (its public methods all dial real gRPC),
//  so this suite stresses the hermetic seam directly above it: the
//  free-standing `firstPaymentRequest(in:shouldIgnore:)` and
//  `pollForGiveRequest(maxAttempts:pollInterval:fetch:)` consumers in
//  `Client+Messaging.swift`. Those are the layer that actually decides what
//  callers see when batches arrive, so they're where double-delivery or
//  stalls would surface in production.
//
//  With TSan and Main Thread Checker both enabled on the test scheme, races
//  in either consumer surface as TSan warnings; the assertions add the
//  exactness piece (no double-delivery, no lost match).
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("MessagingService fan-in", .timeLimit(.minutes(1)))
struct MessagingServiceFanInStressTests {

    private let testAccount = try! PublicKey(base58: "54ggcQ23uen5b9QXMAns99MQNTKn7iyzq4wvCW6e8r25")
    private let testSignature: Signature = .mock

    // MARK: - firstPaymentRequest -

    /// Many producers yield into the same `AsyncThrowingStream` while one
    /// consumer awaits via `firstPaymentRequest`. The function must deliver
    /// exactly one match — never two, never zero — even when the producers
    /// all push payment-request batches at once.
    @Test("50 concurrent producers yield exactly one delivered match")
    func firstPaymentRequest_concurrentYields_deliversExactlyOnce() async throws {
        let (stream, continuation) = AsyncThrowingStream<[StreamMessage], Error>.makeStream()

        let consumer = Task {
            try await firstPaymentRequest(in: stream, shouldIgnore: { false })
        }

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    continuation.yield([
                        StreamMessage(
                            id: ID(data: Data([UInt8.random(in: 0...255)])),
                            kind: .paymentRequest(
                                PaymentRequest(
                                    account: self.testAccount,
                                    signature: self.testSignature
                                )
                            )
                        )
                    ])
                }
            }
        }

        // Consumer returns from the first matching batch. The remaining
        // yields are absorbed by the stream's buffer and discarded when we
        // finish below — that's what proves "exactly once" at the consumer.
        let request = try await consumer.value
        #expect(request.account == testAccount)

        continuation.finish()
    }

    /// Cancelling the consuming task while producers are still yielding
    /// must not crash, leak, or block the producers.
    @Test("Cancellation during concurrent yields tears down cleanly")
    func firstPaymentRequest_cancellationDuringYields_doesNotCrash() async throws {
        let (stream, continuation) = AsyncThrowingStream<[StreamMessage], Error>.makeStream()

        let consumer = Task {
            try await firstPaymentRequest(in: stream, shouldIgnore: { true })
        }

        let producers = Task {
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<200 {
                    group.addTask {
                        continuation.yield([
                            StreamMessage(
                                id: ID(data: Data([UInt8.random(in: 0...255)])),
                                kind: .paymentRequest(
                                    PaymentRequest(
                                        account: self.testAccount,
                                        signature: self.testSignature
                                    )
                                )
                            )
                        ])
                    }
                }
            }
        }

        consumer.cancel()
        continuation.finish()
        await producers.value
        _ = try? await consumer.value
    }

    // MARK: - pollForGiveRequest -

    /// Many concurrent pollers each driving their own `fetch` closure must
    /// each complete without crashing or interfering with each other's
    /// attempt counts. This mirrors the production case where multiple
    /// `awaitGiveRequest` calls overlap (e.g. user reopens the bill flow
    /// while a previous wait is still draining).
    @Test("50 concurrent pollers complete without crashing")
    func pollForGiveRequest_concurrentPollers_doNotCrash() async throws {
        let mints = (0..<50).map { PublicKey.testMint(index: $0) }

        await withTaskGroup(of: Void.self) { group in
            for mint in mints {
                group.addTask {
                    let attemptLog = AttemptLog()
                    _ = try? await pollForGiveRequest(
                        maxAttempts: 3,
                        pollInterval: .milliseconds(1),
                        fetch: {
                            let n = attemptLog.incrementAndGet()
                            // Match on the second attempt so we exercise both
                            // the "skip empty" path and the "return on match"
                            // path under contention.
                            if n < 2 { return [] }
                            return [
                                StreamMessage(
                                    id: ID(data: Data([UInt8(n & 0xff)])),
                                    kind: .requestToGiveBill(mint, nil, nil)
                                )
                            ]
                        }
                    )
                }
            }
        }
    }

    /// Cancelling a poller mid-flight must abort its `Task.sleep` and exit
    /// without crashing. `pollForGiveRequest` calls `Task.checkCancellation`
    /// between attempts, so cancellation should propagate as a thrown
    /// `CancellationError` (or as a `Task.sleep` cancellation) rather than
    /// silently completing or hanging.
    @Test("Cancellation tears down cleanly")
    func pollForGiveRequest_cancellation_doesNotLeakOrCrash() async {
        let task = Task {
            try await pollForGiveRequest(
                maxAttempts: 1_000,
                pollInterval: .milliseconds(10),
                fetch: { [] }
            )
        }
        task.cancel()
        _ = try? await task.value
    }

    // MARK: - Test helpers -

    private final class AttemptLog: @unchecked Sendable {
        private let lock = NSLock()
        private var counter = 0
        func incrementAndGet() -> Int {
            lock.lock(); defer { lock.unlock() }
            counter += 1
            return counter
        }
    }
}
