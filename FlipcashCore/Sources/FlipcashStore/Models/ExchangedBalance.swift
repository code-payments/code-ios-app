//
//  ExchangedBalance.swift
//  FlipcashStore
//
//  Created by Dima Bart on 2025-04-23.
//

import Foundation
import FlipcashCore

/// A stored balance paired with its fiat value at a given rate.
public struct ExchangedBalance: Identifiable, Hashable, Sendable {
    public let stored: StoredBalance
    public let exchangedFiat: ExchangedFiat

    public init(stored: StoredBalance, exchangedFiat: ExchangedFiat) {
        self.stored = stored
        self.exchangedFiat = exchangedFiat
    }

    public var id: PublicKey {
        stored.id
    }
}

extension Array where Element == ExchangedBalance {

    /// Balances eligible to give, send, or tip.
    public func giveable() -> [ExchangedBalance] {
        fundable()
    }

    /// These balances without Dollars, for a picker that names a community currency: dollars
    /// is the stable token, not one.
    public func excludingUSDF() -> [ExchangedBalance] {
        filter { $0.stored.mint != .usdf }
    }

    /// The community currencies these balances hold, in the order a community-currency picker lists
    /// them: the giveable balances without Dollars.
    public func communityCurrencies() -> [ExchangedBalance] {
        giveable().excludingUSDF()
    }

    /// Balances eligible to withdraw.
    public func withdrawable() -> [ExchangedBalance] {
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

extension Array where Element == StoredBalance {
    /// These balances at `rate`, as the app's balance lists show them: every mint that converts to
    /// a displayable value, and Dollars at any value so the wallet can show a zero Dollars card.
    public func exchanged(with rate: Rate) -> [ExchangedBalance] {
        compactMap { stored in
            let balance = stored.exchanged(with: rate)
            guard stored.mint == .usdf || balance.exchangedFiat.hasDisplayableValue() else {
                return nil
            }
            return balance
        }
    }
}

extension StoredBalance {
    /// This balance paired with its fiat value at `rate`.
    public func exchanged(with rate: Rate) -> ExchangedBalance {
        ExchangedBalance(stored: self, exchangedFiat: computeExchangedValue(with: rate))
    }
}
