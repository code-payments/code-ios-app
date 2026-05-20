//
//  DialogItem+CashFlows.swift
//  Code
//
//  Created by Raul Riera on 2026-04-29.
//

import FlipcashUI

extension DialogItem {

    /// Coinbase Onramp rejects orders below `CoinbaseFundingOperation.minimumPurchaseUSD`
    /// with a generic error; surface the constraint up-front instead of letting
    /// the user round-trip to Apple Pay. `minimum` is the USD floor already
    /// formatted in the user's selected display currency.
    static func applePayMinimumPurchase(minimum: String) -> DialogItem {
        .error(
            title: "\(minimum) Minimum Purchase",
            subtitle: "Please enter an amount of \(minimum) or higher"
        )
    }

    /// Onboarding nudge surfaced when the user attempts to Give without any
    /// giveable balance. Used from the Scan screen and from the give deep
    /// link path — both call sites pass the same router's `present(.discover)`.
    static func noGiveableBalance(onDiscover: @escaping () -> Void) -> DialogItem {
        .info(
            title: "No Balance Yet",
            subtitle: "Buy a currency to get started, or get another Flipcash user to give you some cash"
        ) {
            .standard("Discover Currencies", action: onDiscover);
            .cancel()
        }
    }
}
