//
//  AppRouterReturnToRootTests.swift
//  FlipcashTests
//
//  Created by Raul Riera on 2026-05-08.
//

import SwiftUI
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("AppRouter Return To Root")
struct AppRouterReturnToRootTests {

    @Test("returnToRoot with a presented sheet clears presentedSheet")
    func returnToRoot_withPresentedSheet_clearsPresentedSheet() {
        let router = AppRouter()
        router.present(.balance)

        router.returnToRoot()

        #expect(router.presentedSheet == nil)
    }

    @Test("returnToRoot clears every non-dismissing stack's path synchronously")
    func returnToRoot_withPopulatedStacks_clearsNonDismissingStacks() {
        let router = AppRouter()

        // Seed every stack independently of which sheet is presented so we can
        // assert the synchronous clear covers all of them.
        router[.balance]  = AppRouter.navigationPath(.currencyInfo(.usdc))
        router[.settings] = AppRouter.navigationPath(.settingsMyAccount, .settingsAdvancedFeatures)
        router[.give]     = AppRouter.navigationPath(.give(.usdc))
        router[.discover] = AppRouter.navigationPath(.discoverCurrencies)

        // Present .balance so it's the dismissing sheet; .balance's path is
        // kept through the dismiss animation and cleared on next present.
        router.present(.balance)
        router.returnToRoot()

        #expect(router[.settings].isEmpty)
        #expect(router[.give].isEmpty)
        #expect(router[.discover].isEmpty)
        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdc)),
                "the dismissing stack keeps its path so the slide-down animates with current contents")
    }

    @Test("re-presenting the dismissed sheet after returnToRoot lands at root")
    func returnToRoot_thenPresentSameSheet_landsAtRoot() {
        let router = AppRouter()
        router.present(.balance)
        router.push(.currencyInfo(.usdc))
        router.push(.transactionHistory(.usdc))

        router.returnToRoot()
        router.present(.balance)

        #expect(router[.balance].isEmpty,
                "the previously dismissed sheet's path is cleared on re-present")
    }

    @Test("presenting a different sheet after returnToRoot lands at root for that stack")
    func returnToRoot_thenPresentOtherSheet_landsAtRoot() {
        let router = AppRouter()
        router.present(.balance)
        // Seed another stack out-of-band before triggering returnToRoot, so the
        // synchronous clear is the only thing that could empty it.
        router[.settings] = AppRouter.navigationPath(.settingsMyAccount, .settingsAdvancedFeatures)

        router.returnToRoot()
        router.present(.settings)

        #expect(router[.settings].isEmpty,
                "non-dismissing stacks are cleared synchronously by returnToRoot")
    }

    @Test("returnToRoot with no presented sheet still clears all stack paths")
    func returnToRoot_withNoPresentedSheet_clearsAllPaths() {
        let router = AppRouter()
        router[.balance]  = AppRouter.navigationPath(.currencyInfo(.usdc))
        router[.settings] = AppRouter.navigationPath(.settingsMyAccount)

        router.returnToRoot()

        #expect(router.presentedSheet == nil)
        #expect(router[.balance].isEmpty)
        #expect(router[.settings].isEmpty)
        #expect(router[.give].isEmpty)
        #expect(router[.discover].isEmpty)
    }

    @Test("returnToRoot is idempotent across consecutive calls")
    func returnToRoot_calledTwice_endStateMatchesSingleCall() {
        let router = AppRouter()
        router.present(.balance)
        router.push(.currencyInfo(.usdc))
        router[.settings] = AppRouter.navigationPath(.settingsMyAccount)

        router.returnToRoot()
        router.returnToRoot()

        #expect(router.presentedSheet == nil)
        #expect(router[.balance].isEmpty)
        #expect(router[.settings].isEmpty)
        #expect(router[.give].isEmpty)
        #expect(router[.discover].isEmpty)
    }
}
