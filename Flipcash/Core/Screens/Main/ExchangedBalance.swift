//
//  ExchangedBalance.swift
//  Code
//
//  Created by Dima Bart on 2025-04-23.
//

import Foundation
import FlipcashCore

/// A stored balance paired with its fiat value at a given rate.
struct ExchangedBalance: Identifiable, Hashable {
    let stored: StoredBalance
    let exchangedFiat: ExchangedFiat

    var id: PublicKey {
        stored.id
    }
}

extension Array where Element == ExchangedBalance {

    /// Balances eligible to give, send, or tip.
    func giveable() -> [ExchangedBalance] {
        fundable()
    }

    /// Balances eligible to withdraw.
    func withdrawable() -> [ExchangedBalance] {
        fundable()
    }

    /// Balances that can fund an outgoing amount. Dollars appears only when it
    /// carries a displayable value: `balances(for:)` keeps USDF at any value so
    /// the wallet can render a zero Dollars card, and a picker that funds an
    /// outgoing amount has no use for a balance that can't fund anything. Every
    /// other mint is already filtered to a displayable value upstream.
    private func fundable() -> [ExchangedBalance] {
        filter { balance in
            guard balance.stored.mint == .usdf else { return true }
            return balance.exchangedFiat.hasDisplayableValue()
        }
    }
}

extension StoredBalance {
    /// This balance paired with its fiat value at `rate`.
    func exchanged(with rate: Rate) -> ExchangedBalance {
        ExchangedBalance(stored: self, exchangedFiat: computeExchangedValue(with: rate))
    }
}
