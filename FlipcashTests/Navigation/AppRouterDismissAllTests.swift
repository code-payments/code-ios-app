//
//  AppRouterDismissAllTests.swift
//  FlipcashTests
//
//  Created by Raul Riera on 2026-05-08.
//

import SwiftUI
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("AppRouter Dismiss All")
struct AppRouterDismissAllTests {

    @Test("dismissAll with a presented sheet clears presentedSheet")
    func dismissAll_withPresentedSheet_clearsPresentedSheet() {
        let router = AppRouter()
        router.present(.balance)

        router.dismissAll()

        #expect(router.presentedSheet == nil)
    }

    @Test("dismissAll clears every non-dismissing stack's path synchronously")
    func dismissAll_withPopulatedStacks_clearsNonDismissingStacks() {
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
        router.dismissAll()

        #expect(router[.settings].isEmpty)
        #expect(router[.give].isEmpty)
        #expect(router[.discover].isEmpty)
        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdc)),
                "the dismissing stack keeps its path so the slide-down animates with current contents")
    }

    @Test("re-presenting the dismissed sheet after dismissAll lands at root")
    func dismissAll_thenPresentSameSheet_landsAtRoot() {
        let router = AppRouter()
        router.present(.balance)
        router.push(.currencyInfo(.usdc))
        router.push(.transactionHistory(.usdc))

        router.dismissAll()
        router.present(.balance)

        #expect(router[.balance].isEmpty,
                "the previously dismissed sheet's path is cleared on re-present")
    }

    @Test("presenting a different sheet after dismissAll lands at root for that stack")
    func dismissAll_thenPresentOtherSheet_landsAtRoot() {
        let router = AppRouter()
        router.present(.balance)
        // Seed another stack out-of-band before triggering dismissAll, so the
        // synchronous clear is the only thing that could empty it.
        router[.settings] = AppRouter.navigationPath(.settingsMyAccount, .settingsAdvancedFeatures)

        router.dismissAll()
        router.present(.settings)

        #expect(router[.settings].isEmpty,
                "non-dismissing stacks are cleared synchronously by dismissAll")
    }

    @Test("dismissAll with no presented sheet still clears all stack paths")
    func dismissAll_withNoPresentedSheet_clearsAllPaths() {
        let router = AppRouter()
        router[.balance]  = AppRouter.navigationPath(.currencyInfo(.usdc))
        router[.settings] = AppRouter.navigationPath(.settingsMyAccount)

        router.dismissAll()

        #expect(router.presentedSheet == nil)
        #expect(router[.balance].isEmpty)
        #expect(router[.settings].isEmpty)
        #expect(router[.give].isEmpty)
        #expect(router[.discover].isEmpty)
    }

    @Test("dismissAll is idempotent across consecutive calls")
    func dismissAll_calledTwice_endStateMatchesSingleCall() {
        let router = AppRouter()
        router.present(.balance)
        router.push(.currencyInfo(.usdc))
        router[.settings] = AppRouter.navigationPath(.settingsMyAccount)

        router.dismissAll()
        router.dismissAll()

        #expect(router.presentedSheet == nil)
        #expect(router[.balance].isEmpty)
        #expect(router[.settings].isEmpty)
        #expect(router[.give].isEmpty)
        #expect(router[.discover].isEmpty)
    }

    // MARK: - dismissAll(presenting:)

    @Test("dismissAll(presenting:) from nested-buy state lands on the target root")
    func dismissAll_presenting_fromNestedBuy_landsOnTarget() {
        let router = AppRouter()
        router.present(.balance)
        router.push(.currencyInfo(.usdc))
        router.presentNested(.buy(.usdc))

        router.dismissAll(presenting: .usdcDeposit)

        #expect(router.presentedSheets == [.usdcDeposit])
        #expect(router[.buy].isEmpty)

        router.present(.balance)
        #expect(router[.balance].isEmpty,
                "balance path must clear on next present after dismissAll(presenting:)")
    }

    @Test("dismissAll(presenting:) from empty state mounts the new root with a clean path")
    func dismissAll_presenting_fromEmpty_mountsNewRoot() {
        let router = AppRouter()
        router[.usdcDeposit] = AppRouter.navigationPath(.usdcDepositAddress)

        router.dismissAll(presenting: .usdcDeposit)

        #expect(router.presentedSheets == [.usdcDeposit])
        #expect(router[.usdcDeposit].isEmpty,
                "the target stack's path must be cleared so the new sheet mounts at root")
    }

    @Test("dismissAll(presenting:) clears the target stack's path when previously dismissed")
    func dismissAll_presenting_clearsTargetStaleness() {
        let router = AppRouter()
        router.present(.usdcDeposit)
        router.push(.usdcDepositAddress)
        router.dismissSheet()

        router.present(.balance)
        router.dismissAll(presenting: .usdcDeposit)

        #expect(router.presentedSheets == [.usdcDeposit])
        #expect(router[.usdcDeposit].isEmpty)
    }

    @Test("dismissAll(presenting:) re-presenting the dismissing root clears its stale path")
    func dismissAll_presenting_sameAsDismissingRoot_clearsPath() {
        let router = AppRouter()
        router.present(.balance)
        router.push(.currencyInfo(.usdc))

        router.dismissAll(presenting: .balance)

        #expect(router.presentedSheets == [.balance])
        #expect(router[.balance].isEmpty,
                "re-presenting the same root via dismissAll(presenting:) must clear its stale path")
    }
}
