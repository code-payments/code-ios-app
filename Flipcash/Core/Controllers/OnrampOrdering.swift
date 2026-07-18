//
//  OnrampOrdering.swift
//  Flipcash
//

import Foundation

/// Coinbase onramp-order surface used by `CoinbaseDepositOperation` and the
/// session-scoped Coinbase service. Conformers POST a new guest-checkout
/// order and return Coinbase's response (order id + payment link).
protocol OnrampOrdering: Sendable {

    /// Submits the order to Coinbase.
    func createOrder(request: OnrampOrderRequest) async throws -> OnrampOrderResponse
}

extension Coinbase: OnrampOrdering {}
