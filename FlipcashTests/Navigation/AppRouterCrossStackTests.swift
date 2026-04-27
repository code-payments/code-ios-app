//
//  AppRouterCrossStackTests.swift
//  FlipcashTests
//
//  Created by Raul Riera on 2026-04-27.
//

import SwiftUI
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("AppRouter Cross-Stack Navigation")
struct AppRouterCrossStackTests {

    @Test("From cold state, navigate opens owning sheet with destination on top")
    func navigate_fromColdState_opensOwningStack() {
        let router = AppRouter()
        router.navigate(to: .currencyInfo(.usdc))
        #expect(router.presentedSheet == .balance)
        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdc)))
    }

    @Test("Navigating to a destination on a different stack swaps the sheet")
    func navigate_acrossStacks_swapsSheet() {
        let router = AppRouter()
        router.present(.settings)
        router.setPath([.settingsMyAccount, .settingsAdvancedFeatures], on: .settings)

        router.navigate(to: .currencyInfo(.usdc))

        #expect(router.presentedSheet == .balance)
        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdc)))
    }

    @Test("Sheet swap preserves the other stack's path for return trips")
    func navigate_acrossStacks_preservesOtherStackPath() {
        let router = AppRouter()
        router.present(.settings)
        let settingsPath: [AppRouter.Destination] = [.settingsMyAccount, .settingsAdvancedFeatures]
        router.setPath(settingsPath, on: .settings)

        router.navigate(to: .currencyInfo(.usdc))

        #expect(router[.settings] == AppRouter.navigationPath(.settingsMyAccount, .settingsAdvancedFeatures),
                "settings path must survive the sheet swap")
    }

    @Test("Same-stack navigate replaces the path on that stack")
    func navigate_sameStack_replacesPath() {
        let router = AppRouter()
        router.present(.balance)
        router.setPath([.currencyInfo(.usdc), .transactionHistory(.usdc)], on: .balance)

        router.navigate(to: .currencyInfo(.usdf))

        #expect(router.presentedSheet == .balance)
        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdf)))
    }

    @Test("Push notification routing to a settings destination from balance swaps to settings")
    func navigate_fromBalanceToSettingsDestination_swapsToSettings() {
        let router = AppRouter()
        router.present(.balance)
        router.setPath([.currencyInfo(.usdc)], on: .balance)

        router.navigate(to: .settingsApplicationLogs)

        #expect(router.presentedSheet == .settings)
        #expect(router[.settings] == AppRouter.navigationPath(.settingsApplicationLogs))
        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdc)),
                "balance preserved underneath")
    }

    @Test("Navigate is idempotent when target state already matches current state")
    func navigate_isIdempotent() {
        let router = AppRouter()
        router.navigate(to: .currencyInfo(.usdc))
        router.navigate(to: .currencyInfo(.usdc))
        #expect(router.presentedSheet == .balance)
        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdc)))
    }

    @Test("owningStack maps wallet destinations to .balance")
    func owningStack_walletDestinations_mapToBalance() {
        #expect(AppRouter.Destination.currencyInfo(.usdc).owningStack == .balance)
        #expect(AppRouter.Destination.discoverCurrencies.owningStack == .balance)
        #expect(AppRouter.Destination.currencyCreationSummary.owningStack == .balance)
        #expect(AppRouter.Destination.currencyCreationWizard.owningStack == .balance)
        #expect(AppRouter.Destination.transactionHistory(.usdc).owningStack == .balance)
    }

    @Test("owningStack maps settings destinations to .settings")
    func owningStack_settingsDestinations_mapToSettings() {
        #expect(AppRouter.Destination.settingsMyAccount.owningStack == .settings)
        #expect(AppRouter.Destination.settingsAdvancedFeatures.owningStack == .settings)
        #expect(AppRouter.Destination.settingsAppSettings.owningStack == .settings)
        #expect(AppRouter.Destination.settingsBetaFlags.owningStack == .settings)
        #expect(AppRouter.Destination.settingsAccountSelection.owningStack == .settings)
        #expect(AppRouter.Destination.settingsApplicationLogs.owningStack == .settings)
        #expect(AppRouter.Destination.accessKey.owningStack == .settings)
        #expect(AppRouter.Destination.depositCurrencyList.owningStack == .settings)
        #expect(AppRouter.Destination.withdraw.owningStack == .settings)
    }

    @Test("Stack.sheet maps each stack to its corresponding sheet")
    func stackSheet_isOneToOne() {
        #expect(AppRouter.Stack.balance.sheet == .balance)
        #expect(AppRouter.Stack.settings.sheet == .settings)
        #expect(AppRouter.Stack.give.sheet == .give)
    }
}
