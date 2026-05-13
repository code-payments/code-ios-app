//
//  DialogItem+Buy.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-05-13.
//

import FlipcashUI

extension DialogItem {

    /// Coinbase Onramp rejects orders below $5 USD with a generic error;
    /// surface the constraint up-front instead of letting the user round-trip
    /// to Apple Pay. `minimum` is the $5 USD equivalent already formatted in
    /// the user's selected display currency.
    static func applePayMinimumPurchase(minimum: String) -> DialogItem {
        .init(
            style: .destructive,
            title: "\(minimum) Minimum Purchase",
            subtitle: "Please enter an amount of \(minimum) or higher",
            dismissable: true
        ) {
            .okay(kind: .destructive)
        }
    }
}
