//
//  CurrencySelection.swift
//  Flipcash
//

import FlipcashCore

extension Array where Element == ExchangedBalance {

    /// Balances eligible to send or give — every balance except USDF, the
    /// on-Flipcash stablecoin, which is never transferred peer-to-peer.
    var giveable: [ExchangedBalance] {
        filter { $0.stored.mint != .usdf }
    }
}

enum CurrencySelection {

    /// The balance an amount-entry flow (Send, Give) should open with. An
    /// explicit `mint` wins; otherwise the global token selection when it's
    /// giveable, else the highest-value giveable balance — the fallback covers a
    /// stale or USDF global selection.
    static func resolveInitialBalance(
        mint: PublicKey?,
        session: Session,
        ratesController: RatesController
    ) -> ExchangedBalance? {
        let rate = ratesController.rateForBalanceCurrency()

        if let mint, let stored = session.balance(for: mint) {
            return stored.exchanged(with: rate)
        }

        let giveable = session.balances(for: rate).giveable

        if let stored = ratesController.selectedTokenMint,
           let match = giveable.first(where: { $0.stored.mint == stored }) {
            return match
        }

        return giveable.first
    }
}
