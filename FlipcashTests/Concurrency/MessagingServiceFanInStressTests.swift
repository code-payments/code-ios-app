//
//  MessagingServiceFanInStressTests.swift
//  FlipcashTests
//
//  TSan + Main Thread Checker sentinel for the `MessagingService` fan-in
//  consumers. `MessagingService` opens the long-lived gRPC message stream
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
//  in either consumer surface as TSan warnings. Single-delivery is
//  structural in `firstPaymentRequest` (it returns on first match), so
//  these tests target crash/leak/hang under contention rather than
//  asserting an exactly-once property the helper already guarantees.
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite(
    "MessagingService fan-in",
    .timeLimit(.minutes(1)),
    .tags(.concurrency, .stress)
)
struct MessagingServiceFanInStressTests {

    private let testAccount = PublicKey.jeffy
    private let testSignature: Signature = .mock

    // MARK: - firstPaymentRequest -

    /// Many producers yield into the same `AsyncThrowingStream` while one
    /// consumer awaits via `firstPaymentRequest`. The consumer must return
    /// the first matching request without crashing or hanging when the
    /// producers all push payment-request batches at once.
    @Test("50 concurrent producers — first-match returns once")
    func firstPaymentRequest_concurrentYields_returnsFirstMatchUnderContention() async throws {
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

        // The helper returns on the first matching batch (`for try await ...
        // return`), so single-delivery is structural rather than asserted
        // here — we're just checking the returned account survives contention.
        // Remaining yields are absorbed by the stream buffer and discarded
        // when we finish below.
        let request = try await consumer.value
        #expect(request.account == testAccount)

        continuation.finish()
    }

    /// Cancelling the consuming task while producers are still yielding
    /// must not crash, leak, or block the producers.
    @Test("Cancellation during concurrent yields tears down cleanly")
    func firstPaymentRequest_cancellationDuringYields_doesNotCrash() async throws {
        let (stream, continuation) = AsyncThrowingStream<[StreamMessage], Error>.makeStream()

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

        // Single-iteration stress: the consumer is a one-shot await, so we
        // run it once inside the helper which adds the warmup before cancel.
        await runThrowingCancellationStress(iterations: 1) { [stream] in
            _ = try await firstPaymentRequest(in: stream, shouldIgnore: { true })
        }

        continuation.finish()
        await producers.value
    }

    // MARK: - pollForGiveRequest -

    /// Cancelling a poller mid-flight must abort its `Task.sleep` and exit
    /// without crashing. `pollForGiveRequest` calls `Task.checkCancellation`
    /// between attempts, so cancellation should propagate as a thrown
    /// `CancellationError` (or as a `Task.sleep` cancellation) rather than
    /// silently completing or hanging.
    @Test("Cancellation tears down cleanly")
    func pollForGiveRequest_cancellation_doesNotLeakOrCrash() async {
        // Single-iteration stress: the poller is one long-running call that
        // sleeps between attempts, so we run it once inside the helper which
        // adds the warmup before cancel.
        await runThrowingCancellationStress(iterations: 1) {
            _ = try await pollForGiveRequest(
                maxAttempts: 1_000,
                pollInterval: .milliseconds(10),
                fetch: { [] }
            )
        }
    }
}
