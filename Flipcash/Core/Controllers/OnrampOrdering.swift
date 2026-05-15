//
//  OnrampOrdering.swift
//  Flipcash
//

import Foundation

/// Coinbase onramp-order surface used by `CoinbaseFundingOperation` and the
/// session-scoped Coinbase service. Conformers POST a new guest-checkout
/// order and return Coinbase's response (order id + payment link).
protocol OnrampOrdering: Sendable {

    /// Submits the order to Coinbase. `idempotencyKey` lets the caller retry
    /// without risking a duplicate order on a transient transport failure.
    func createOrder(
        request: OnrampOrderRequest,
        idempotencyKey: UUID?
    ) async throws -> OnrampOrderResponse
}

extension Coinbase: OnrampOrdering {}
