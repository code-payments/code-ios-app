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

    /// Balances eligible to give, send, or tip. Dollars appears only when it
    /// carries a displayable value: `balances(for:)` keeps USDF at any value so
    /// the wallet can render a zero Dollars card, and an amount-entry picker has
    /// no use for a balance that can't fund anything.
    func giveable() -> [ExchangedBalance] {
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
