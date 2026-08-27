//
//  BuyFlowTitle.swift
//  Flipcash
//

import FlipcashCore

/// Titles the buy flow's screens after the currency-info tile that opened them.
enum BuyFlowTitle {

    /// "Buy More" for a currency the account already holds, "Buy In" for one it
    /// doesn't. Held is the same displayable-value test the tiles use, so a
    /// balance too small to display still reads as "Buy In".
    @MainActor
    static func forCurrency(
        _ mint: PublicKey,
        session: Session,
        ratesController: RatesController
    ) -> String {
        guard let stored = session.balance(for: mint) else { return "Buy In" }
        let rate = ratesController.rateForBalanceCurrency()
        return stored.exchanged(with: rate).exchangedFiat.hasDisplayableValue() ? "Buy More" : "Buy In"
    }
}
