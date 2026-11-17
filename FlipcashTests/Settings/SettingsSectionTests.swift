//
//  SettingsSectionTests.swift
//  FlipcashTests
//

import SwiftUI
import Testing
@testable import Flipcash

@MainActor
@Suite("Settings sections")
struct SettingsSectionTests {

    @Test("Without the Group Money shell, Settings lists no Currencies section")
    func visible_withoutShell_hasNoCurrencies() {
        #expect(SettingsSection.visible(showsGroupMoney: false) == [.security, .privacy, .advanced, .account])
    }

    @Test("With the Group Money shell, Currencies sits between Privacy and Advanced")
    func visible_withShell_placesCurrenciesBetweenPrivacyAndAdvanced() {
        #expect(SettingsSection.visible(showsGroupMoney: true) == [.security, .privacy, .currencies, .advanced, .account])
    }

    @Test("Create Your Own Currency comes before Currency Leaderboard")
    func currencyRows_titlesInOrder() {
        #expect(SettingsCurrencyRow.allCases.map(\.title) == ["Create Your Own Currency", "Currency Leaderboard"])
    }

    @Test("Each Currencies row pushes the screen the wallet tile for it opens, onto the Settings stack")
    func currencyRows_pushTheirScreenOverSettings() {
        let cases: [(SettingsCurrencyRow, AppRouter.Destination)] = [
            (.createCurrency, .currencyCreationSummary),
            (.leaderboard, .discoverCurrencies),
        ]
        for (row, destination) in cases {
            let router = AppRouter()
            router.activeTabStack = .you
            router.push(.settings)

            row.open(using: router)

            var expected = NavigationPath()
            expected.append(AppRouter.Destination.settings)
            expected.append(destination)
            #expect(router[.you] == expected, "\(row)")
            #expect(router[.balance].isEmpty, "\(row) must not reach the Wallet stack")
        }
    }
}
