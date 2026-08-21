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

    @Test("From cold state, navigate to a tab-owned destination requests its tab")
    func navigate_fromColdState_requestsOwningTab() {
        let router = AppRouter()
        router.navigate(to: .currencyInfo(.usdc))
        #expect(router.presentedSheets.isEmpty, "a tab stack is reached by bringing its tab forward")
        #expect(router.requestedTabStack == .balance)
        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdc)))
    }

    @Test("Navigating to a tab-owned destination dismisses whatever sheet is up")
    func navigate_fromSheetToTabStack_dismissesSheet() {
        let router = AppRouter()
        router.present(.settings)
        router.setPath([.settingsMyAccount, .settingsAdvancedFeatures], on: .settings)

        router.navigate(to: .currencyInfo(.usdc))

        #expect(router.presentedSheets.isEmpty)
        #expect(router.requestedTabStack == .balance)
        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdc)))
    }

    @Test("Routing to a tab-hosted stack leaves the other tabs' paths alone")
    func navigate_toTabStack_preservesOtherTabPaths() {
        let router = AppRouter()
        router.activeTabStack = .balance
        router.setPath([.currencyInfo(.usdc), .transactionHistory(.usdc)], on: .balance)

        router.navigate(to: .tipcard)

        #expect(router.requestedTabStack == .tips, "the Chat tab hosts the tips stack")
        #expect(router.presentedSheets.isEmpty, "the tips sheet is for surfaces that have no tab bar")
        #expect(router[.tips] == AppRouter.navigationPath(.tipcard))
        #expect(
            router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdc), .transactionHistory(.usdc)),
            "the wallet tab is untouched behind the tab switch"
        )
    }

    @Test("Same-stack navigate replaces the path on that stack")
    func navigate_sameStack_replacesPath() {
        let router = AppRouter()
        router.activeTabStack = .balance
        router.setPath([.currencyInfo(.usdc), .transactionHistory(.usdc)], on: .balance)

        router.navigate(to: .currencyInfo(.usdf))

        #expect(router.presentedSheets.isEmpty)
        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdf)))
    }

    @Test("Push notification routing to a settings destination from the wallet tab presents settings")
    func navigate_fromWalletTabToSettingsDestination_presentsSettings() {
        let router = AppRouter()
        router.activeTabStack = .balance
        router.setPath([.currencyInfo(.usdc)], on: .balance)

        router.navigate(to: .settingsApplicationLogs)

        #expect(router.presentedSheet == .settings)
        #expect(router[.settings] == AppRouter.navigationPath(.settingsApplicationLogs))
        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdc)),
                "the wallet tab is preserved underneath")
    }

    @Test("Navigate is idempotent when target state already matches current state")
    func navigate_isIdempotent() {
        let router = AppRouter()
        router.navigate(to: .currencyInfo(.usdc))

        // Stand in for HomeTabView consuming the request and reporting the
        // selection back; without it the router can't know the tab is already up.
        router.activeTabStack = .balance
        router.requestedTabStack = nil

        router.navigate(to: .currencyInfo(.usdc))

        #expect(router.requestedTabStack == nil, "a redundant navigate must not re-request the tab")
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
            (AppRouter.Destination.withdrawCurrency(.usdc),         AppRouter.Stack.balance),
            (AppRouter.Destination.usdcDepositEducation,            AppRouter.Stack.balance),
            (AppRouter.Destination.usdcDepositAddress,              AppRouter.Stack.balance),
            (AppRouter.Destination.settingsMyAccount,               AppRouter.Stack.settings),
            (AppRouter.Destination.settingsAdvancedFeatures,        AppRouter.Stack.settings),
            (AppRouter.Destination.settingsAppSettings,             AppRouter.Stack.settings),
            (AppRouter.Destination.settingsBetaFlags,               AppRouter.Stack.settings),
            (AppRouter.Destination.settingsAccountSelection,        AppRouter.Stack.settings),
            (AppRouter.Destination.settingsApplicationLogs,         AppRouter.Stack.settings),
            (AppRouter.Destination.accessKey,                       AppRouter.Stack.settings),
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
        "Destination.payload exposes the mint for mint-bearing cases",
        arguments: [
            (AppRouter.Destination.withdrawCurrency(.usdc),         PublicKey.usdc.base58 as String?),
            (AppRouter.Destination.currencyInfo(.usdf),             PublicKey.usdf.base58 as String?),
            (AppRouter.Destination.usdcDepositEducation,            nil),
            (AppRouter.Destination.usdcDepositAddress,              nil),
            (AppRouter.Destination.withdraw,                        nil),
        ]
    )
    func destination_payloadIsCorrect(
        _ destination: AppRouter.Destination,
        expected: String?
    ) {
        #expect(destination.payload == expected)
    }

    @Test(
        "Stack maps to its sheet presentation",
        arguments: [
            (AppRouter.Stack.settings, AppRouter.SheetPresentation.settings),
            (AppRouter.Stack.give,     AppRouter.SheetPresentation.give),
            (AppRouter.Stack.tips,     AppRouter.SheetPresentation.tips),
        ]
    )
    func stack_mapsToSheet(_ stack: AppRouter.Stack, expected: AppRouter.SheetPresentation) {
        #expect(stack.sheet == expected)
    }

    @Test(
        "Stacks with no root sheet of their own",
        arguments: [AppRouter.Stack.balance, .you, .buy, .addMoney, .sendAmount]
    )
    func stack_withoutSheet_isNil(_ stack: AppRouter.Stack) {
        #expect(stack.sheet == nil, "\(stack) is either a tab stack or nested-only")
    }

    @Test("isTabHosted tracks the tab bar's stacks exactly")
    func tabHostedStacks_matchHomeTabs() {
        #expect(
            Set(AppRouter.Stack.allCases.filter(\.isTabHosted)) == Set(HomeTab.allCases.compactMap(\.pushStack)),
            "AppRouter.Stack.isTabHosted is what navigate(to:) routes on — it must track HomeTab.pushStack"
        )
    }
}
