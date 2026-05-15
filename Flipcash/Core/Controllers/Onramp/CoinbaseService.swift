//
//  CoinbaseService.swift
//  Flipcash
//

import Foundation
import Observation
import FlipcashCore

/// Session-scoped holder for the Coinbase Apple Pay flow's shared UI state.
/// `CoinbaseFundingOperation` publishes the order here so the root-level
/// `OnrampHostModifier` can mount its WebView overlay; the WebView yields
/// `ApplePayEvent`s back through `receiveApplePayEvent`, which feed the
/// operation's `applePayEvents` consumer.
///
/// One service instance per `SessionContainer` lifetime. Operations are
/// per-attempt and consume the stream during their `start()`.
@Observable
@MainActor
final class CoinbaseService {

    /// Drives the WebView overlay. Non-nil while a Coinbase order is
    /// in flight; cleared once the operation completes (success or
    /// failure).
    private(set) var coinbaseOrder: OnrampOrderResponse?

    /// Coinbase CDP API client. `CoinbaseFundingOperation` calls
    /// `createOrder` here; the bearer-token provider was wired at init
    /// from the session's FlipClient.
    @ObservationIgnored let coinbase: any OnrampOrdering

    /// Stream of Apple Pay events forwarded from the WebView host. The
    /// active `CoinbaseFundingOperation` iterates this stream during the
    /// `.awaitingExternal(.applePay)` step.
    @ObservationIgnored let applePayEvents: AsyncStream<ApplePayEvent>
    @ObservationIgnored private let eventContinuation: AsyncStream<ApplePayEvent>.Continuation

    init(coinbase: any OnrampOrdering) {
        self.coinbase = coinbase
        var capturedContinuation: AsyncStream<ApplePayEvent>.Continuation!
        self.applePayEvents = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        self.eventContinuation = capturedContinuation
    }

    func setOrder(_ order: OnrampOrderResponse) {
        coinbaseOrder = order
    }

    func clearOrder() {
        coinbaseOrder = nil
    }

    /// Called by `OnrampHostModifier` when the WebView delivers an event.
    /// Yields onto the stream so the active operation receives it.
    func receiveApplePayEvent(_ event: ApplePayEvent) {
        eventContinuation.yield(event)
    }
}

// MARK: - Supporting types -

enum OnrampError: Error {
    case missingCoinbaseApiKey
}
