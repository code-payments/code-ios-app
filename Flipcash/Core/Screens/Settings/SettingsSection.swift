//
//  SettingsSection.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// A section of the Settings list.
enum SettingsSection: Hashable {
    case security
    case privacy
    case currencies
    case advanced
    case account

    /// The sections Settings lists, top to bottom. Currencies shows only with the
    /// Group Money shell, whose Money screen has no Create Your Own Currency or
    /// Currency Leaderboard tile.
    static func visible(showsGroupMoney: Bool) -> [SettingsSection] {
        if showsGroupMoney {
            [.security, .privacy, .currencies, .advanced, .account]
        } else {
            [.security, .privacy, .advanced, .account]
        }
    }
}

/// A row of the Currencies section, in the order the section lists them.
enum SettingsCurrencyRow: CaseIterable {
    case createCurrency
    case leaderboard

    /// The row's label.
    var title: String {
        switch self {
        case .createCurrency: "Create Your Own Currency"
        case .leaderboard:    "Currency Leaderboard"
        }
    }

    /// The glyph the wallet's tile for the same screen draws.
    var icon: Icon {
        switch self {
        case .createCurrency: .coinsAdd
        case .leaderboard:    .globe
        }
    }

    /// The identifier UI tests find the row by.
    var accessibilityIdentifier: String {
        switch self {
        case .createCurrency: "settings-create-currency-row"
        case .leaderboard:    "settings-currency-leaderboard-row"
        }
    }

    /// Opens the row's screen on the visible stack, the one Settings is on.
    func open(using router: AppRouter) {
        switch self {
        case .createCurrency: router.push(.currencyCreationSummary)
        case .leaderboard:    router.push(.discoverCurrencies)
        }
    }
}
