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

    @Test(
        "Destination maps to its owning stack",
        arguments: [
            (AppRouter.Destination.currencyInfo(.usdc),             AppRouter.Stack.balance),
            (AppRouter.Destination.currencyInfoForDeposit(.usdc),   AppRouter.Stack.balance),
            (AppRouter.Destination.discoverCurrencies,              AppRouter.Stack.balance),
            (AppRouter.Destination.currencyCreationSummary,         AppRouter.Stack.balance),
            (AppRouter.Destination.currencyCreationWizard,          AppRouter.Stack.balance),
            (AppRouter.Destination.transactionHistory(.usdc),       AppRouter.Stack.balance),
            (AppRouter.Destination.give(.usdc),                     AppRouter.Stack.balance),
            (AppRouter.Destination.settingsMyAccount,               AppRouter.Stack.settings),
            (AppRouter.Destination.settingsAdvancedFeatures,        AppRouter.Stack.settings),
            (AppRouter.Destination.settingsAppSettings,             AppRouter.Stack.settings),
            (AppRouter.Destination.settingsBetaFlags,               AppRouter.Stack.settings),
            (AppRouter.Destination.settingsAccountSelection,        AppRouter.Stack.settings),
            (AppRouter.Destination.settingsApplicationLogs,         AppRouter.Stack.settings),
            (AppRouter.Destination.accessKey,                       AppRouter.Stack.settings),
            (AppRouter.Destination.depositCurrencyList,             AppRouter.Stack.settings),
            (AppRouter.Destination.deposit(.usdc),                  AppRouter.Stack.settings),
            (AppRouter.Destination.withdraw,                        AppRouter.Stack.settings),
        ]
    )
    func destination_hasCorrectOwningStack(
        _ destination: AppRouter.Destination,
        expected: AppRouter.Stack
    ) {
        #expect(destination.owningStack == expected)
    }

    @Test(
        "Stack maps to its sheet presentation",
        arguments: [
            (AppRouter.Stack.balance,  AppRouter.SheetPresentation.balance),
            (AppRouter.Stack.settings, AppRouter.SheetPresentation.settings),
            (AppRouter.Stack.give,     AppRouter.SheetPresentation.give),
        ]
    )
    func stack_mapsToSheet(_ stack: AppRouter.Stack, expected: AppRouter.SheetPresentation) {
        #expect(stack.sheet == expected)
    }
}
