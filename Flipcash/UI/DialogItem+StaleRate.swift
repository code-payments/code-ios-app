//
//  DialogItem+StaleRate.swift
//  Code
//
//  Created by Raul Riera on 2026-04-24.
//

import FlipcashUI

extension DialogItem {
    /// Shown when a submit-time pin fetch can't resolve a fresh rate.
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
