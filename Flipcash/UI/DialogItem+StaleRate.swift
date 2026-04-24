//
//  DialogItem+StaleRate.swift
//  Code
//
//  Created by Raul Riera on 2026-04-24.
//

import FlipcashUI

extension DialogItem {
    /// Presented when a submit-time pin fetch can't resolve a fresh verified
    /// exchange rate. Asks the user to try again; shared across the buy,
    /// sell, and withdraw flows so the copy can't drift.
    static var staleRate: DialogItem {
        .init(
            style: .destructive,
            title: "Rate Unavailable",
            subtitle: "Couldn't get a fresh rate. Please try again.",
            dismissable: true
        ) {
            .okay(kind: .destructive)
        }
    }
}
