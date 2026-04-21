//
//  Client+Messaging.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import Combine

extension Client {

    public func openMessageStream(rendezvous: KeyPair, completion: @MainActor @Sendable @escaping (Result<[StreamMessage], Error>) -> Void) -> AnyCancellable {
        messagingService.openMessageStream(rendezvous: rendezvous, completion: completion)
    }

    /// Async-stream overload of ``openMessageStream(rendezvous:completion:)``.
    /// Each yielded element is a batch of `StreamMessage`s delivered by the
    /// gRPC subscription. Breaking out of the `for try await` loop (or
    /// cancelling the consuming task) tears down the underlying subscription.
    public func openMessageStream(rendezvous: KeyPair) -> AsyncThrowingStream<[StreamMessage], Error> {
        nonisolated(unsafe) let service = messagingService
        return asyncThrowingStream { callback in
            service.openMessageStream(rendezvous: rendezvous) { result in
                callback(result)
            }
        }
    }

    public func fetchMessages(rendezvous: KeyPair) async throws -> [StreamMessage] {
        try await withCheckedThrowingContinuation { c in
            messagingService.fetchMessages(rendezvous: rendezvous) { c.resume(with: $0) }
        }
    }

    public func verifyRequestToGrabBill(destination: PublicKey, rendezvous: PublicKey, signature: Signature) -> Bool {
        messagingService.verifyRequestToGrabBill(destination: destination, rendezvous: rendezvous, signature: signature)
    }

    public func sendRequestToGrabBill(destination: PublicKey, rendezvous: KeyPair) async throws -> Bool {
        try await withCheckedThrowingContinuation { c in
            messagingService.sendRequestToGrabBill(destination: destination, rendezvous: rendezvous) { c.resume(with: $0) }
        }
    }

    public func sendRequestToGiveBill(mint: PublicKey, exchangedFiat: ExchangedFiat, verifiedState: VerifiedState?, rendezvous: KeyPair) async throws -> Bool {
        try await withCheckedThrowingContinuation { c in
            messagingService.sendRequestToGiveBill(mint: mint, exchangedFiat: exchangedFiat, verifiedState: verifiedState, rendezvous: rendezvous) { c.resume(with: $0) }
        }
    }

    // MARK: - Higher-level waits -

    /// Waits for the first grab request (i.e. a `paymentRequest` message) to
    /// arrive on the rendezvous channel. Messages are silently skipped while
    /// `shouldIgnore` returns `true`, so callers can pause processing when
    /// a share sheet or other modal is in front of the bill. `shouldIgnore`
    /// is `async` so callers can read actor-isolated state safely — this
    /// method runs on the generic executor, not the caller's actor.
    ///
    /// Throws ``MessagingWaitError/streamClosedBeforeRequest`` if the stream
    /// terminates before any matching message arrives.
    public func awaitGrabRequest(
        rendezvous: KeyPair,
        shouldIgnore: @escaping @Sendable () async -> Bool = { false }
    ) async throws -> PaymentRequest {
        try await firstPaymentRequest(
            in: openMessageStream(rendezvous: rendezvous),
            shouldIgnore: shouldIgnore
        )
    }

    /// Waits for a give request to be present on the rendezvous channel,
    /// polling `pollMessages` up to `maxAttempts` times spaced by
    /// `pollInterval`. Polling — not streaming — is required here because
    /// the give request is typically published *before* the receiver starts
    /// listening, and the streaming endpoint only delivers messages to
    /// already-connected subscribers. The poll endpoint returns the
    /// currently-queued set, so we see the request whether it was published
    /// before or after we started waiting.
    ///
    /// Throws ``MessagingWaitError/timedOut`` if no give request is
    /// observed within `maxAttempts` × `pollInterval`.
    public func awaitGiveRequest(
        rendezvous: KeyPair,
        maxAttempts: Int = 10,
        pollInterval: Duration = .milliseconds(300)
    ) async throws -> GiveRequest {
        let rendezvous = rendezvous
        return try await pollForGiveRequest(
            maxAttempts: maxAttempts,
            pollInterval: pollInterval,
            fetch: { try await self.fetchMessages(rendezvous: rendezvous) }
        )
    }
}

// MARK: - Stream-consuming helpers (testable) -

/// Consumes `stream` and returns the first `paymentRequest` seen, skipping
/// batches for which `shouldIgnore` returns `true`. Throws
/// ``MessagingWaitError/streamClosedBeforeRequest`` if the stream terminates
/// without a match.
func firstPaymentRequest(
    in stream: AsyncThrowingStream<[StreamMessage], Error>,
    shouldIgnore: @Sendable () async -> Bool
) async throws -> PaymentRequest {
    for try await messages in stream {
        if await shouldIgnore() { continue }
        if let request = messages.compactMap(\.paymentRequest).first {
            return request
        }
    }
    throw MessagingWaitError.streamClosedBeforeRequest
}

/// Polls `fetch` for a rendezvous-channel message batch up to `maxAttempts`
/// times (with `pollInterval` between attempts), returning on the first
/// batch that contains a give request. Throws
/// ``MessagingWaitError/timedOut`` when the budget is exhausted without a
/// match.
func pollForGiveRequest(
    maxAttempts: Int,
    pollInterval: Duration,
    fetch: @Sendable () async throws -> [StreamMessage]
) async throws -> GiveRequest {
    for attempt in 0..<maxAttempts {
        if attempt > 0 {
            try await Task.sleep(for: pollInterval)
        }
        try Task.checkCancellation()
        let messages = try await fetch()
        if let request = messages.compactMap(\.giveRequest).first {
            return request
        }
    }
    throw MessagingWaitError.timedOut
}

// MARK: - Errors -

public enum MessagingWaitError: Swift.Error, Equatable {
    /// The rendezvous stream terminated before the requested message type
    /// arrived.
    case streamClosedBeforeRequest

    /// The bounded wait expired without the requested message type arriving.
    case timedOut
}
