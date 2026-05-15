//
//  AppRouterTests.swift
//  FlipcashTests
//
//  Created by Raul Riera on 2026-04-27.
//

import SwiftUI
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("AppRouter")
struct AppRouterTests {

    // MARK: - push / pop / popToRoot / setPath

    @Test("push appends destination to the stack")
    func push_appendsDestination() {
        let router = AppRouter()
        router.present(.balance)
        router.push(.discoverCurrencies)
        #expect(router[.balance] == AppRouter.navigationPath(.discoverCurrencies))
    }

    @Test("push appends in order across multiple calls")
    func push_appendsInOrder() {
        let router = AppRouter()
        router.present(.balance)
        router.push(.currencyInfo(.usdc))
        router.push(.transactionHistory(.usdc))
        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdc), .transactionHistory(.usdc)))
    }

    @Test("pop removes the top destination")
    func pop_removesTop() {
        let router = AppRouter()
        router.present(.balance)
        router.push(.currencyInfo(.usdc))
        router.push(.transactionHistory(.usdc))
        router.pop(on: .balance)
        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdc)))
    }

    @Test("pop on empty stack is a no-op")
    func pop_onEmpty_isNoop() {
        let router = AppRouter()
        router.pop(on: .balance)
        #expect(router[.balance].isEmpty)
    }

    @Test("popTopmost pops the topmost-sheet stack")
    func popTopmost_popsTopmostSheetStack() {
        let router = AppRouter()
        router.present(.balance)
        router.push(.currencyInfo(.usdc))
        router.push(.transactionHistory(.usdc))
        router.popTopmost()
        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdc)))
    }

    @Test("popTopmost on a nested sheet leaves the root stack untouched")
    func popTopmost_nested_doesNotTouchRoot() {
        let router = AppRouter()
        router.present(.balance)
        router.push(.currencyInfo(.usdc))
        router.presentNested(.buy(.usdc))
        router.push(.usdcDepositEducation)

        router.popTopmost()

        #expect(router[.buy].isEmpty)
        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdc)))
    }

    @Test("popTopmost is a no-op with no sheet presented")
    func popTopmost_noSheet_isNoop() {
        let router = AppRouter()
        router.popTopmost()
        #expect(router[.balance].isEmpty)
    }

    @Test("replaceTopmostAny swaps the top destination for a new value")
    func replaceTopmost_swapsTopDestination() {
        let router = AppRouter()
        router.present(.balance)
        router.push(.currencyInfo(.usdc))
        router.push(.transactionHistory(.usdc))

        router.replaceTopmostAny(AppRouter.Destination.discoverCurrencies)

        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdc), .discoverCurrencies))
    }

    @Test("replaceTopmostAny on a nested sheet leaves the root stack untouched")
    func replaceTopmost_nested_doesNotTouchRoot() {
        let router = AppRouter()
        router.present(.balance)
        router.push(.currencyInfo(.usdc))
        router.presentNested(.buy(.usdc))
        router.push(.usdcDepositEducation)

        router.replaceTopmostAny(AppRouter.Destination.usdcDepositAddress)

        #expect(router[.buy] == AppRouter.navigationPath(.usdcDepositAddress))
        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdc)))
    }

    @Test("replaceTopmostAny on an empty stack appends the value")
    func replaceTopmost_emptyStack_appends() {
        let router = AppRouter()
        router.present(.balance)

        router.replaceTopmostAny(AppRouter.Destination.currencyInfo(.usdc))

        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdc)))
    }

    @Test("replaceTopmostAny is a no-op with no sheet presented")
    func replaceTopmost_noSheet_isNoop() {
        let router = AppRouter()
        router.replaceTopmostAny(AppRouter.Destination.currencyInfo(.usdc))
        #expect(router[.balance].isEmpty)
        #expect(router[.buy].isEmpty)
    }

    @Test("popToRoot clears the stack")
    func popToRoot_clearsStack() {
        let router = AppRouter()
        router.present(.balance)
        router.push(.currencyInfo(.usdc))
        router.push(.transactionHistory(.usdc))
        router.popToRoot(on: .balance)
        #expect(router[.balance].isEmpty)
    }

    @Test("popLast removes the requested number of items")
    func popLast_removesCount() {
        let router = AppRouter()
        router.present(.balance)
        router.push(.currencyInfo(.usdc))
        router.push(.transactionHistory(.usdc))
        router.push(.discoverCurrencies)
        router.popLast(2, on: .balance)
        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdc)))
    }

    @Test("popLast clamps to available depth")
    func popLast_clampsToDepth() {
        let router = AppRouter()
        router.present(.balance)
        router.push(.currencyInfo(.usdc))
        router.popLast(10, on: .balance)
        #expect(router[.balance].isEmpty)
    }

    @Test("setPath replaces the entire path")
    func setPath_replacesPath() {
        let router = AppRouter()
        router.present(.balance)
        router.push(.currencyInfo(.usdc))
        router.setPath([.discoverCurrencies, .currencyCreationSummary], on: .balance)
        #expect(router[.balance] == AppRouter.navigationPath(.discoverCurrencies, .currencyCreationSummary))
    }

    @Test("setPath with identical path is a no-op")
    func setPath_identical_isNoop() {
        let router = AppRouter()
        router.setPath([.currencyInfo(.usdc)], on: .balance)
        router.setPath([.currencyInfo(.usdc)], on: .balance)
        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdc)))
    }

    @Test("pushAny accepts non-Destination Hashable types")
    func pushAny_acceptsHashable() {
        let router = AppRouter()
        router.present(.settings)
        router.push(.withdraw)
        router.pushAny(WithdrawNavigationPath.enterAmount)
        #expect(router[.settings].count == 2)
    }

    // MARK: - Stack inference

    @Test("push lands on the currently-presented sheet's stack")
    func push_landsOnPresentedStack() {
        let router = AppRouter()
        router.present(.balance)
        router.push(.currencyInfo(.usdc))
        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdc)))
        #expect(router[.settings].isEmpty)
        #expect(router[.give].isEmpty)
    }

    @Test("push is a no-op when no sheet is presented")
    func push_noopWhenNoSheet() {
        let router = AppRouter()
        router.push(.currencyInfo(.usdc))
        #expect(router[.balance].isEmpty)
        #expect(router[.settings].isEmpty)
        #expect(router[.give].isEmpty)
    }

    @Test("push routes to the current presented stack across sheet swaps")
    func push_acrossSheetSwap_landsOnCurrentStack() {
        // Regression guard: a hardcoded explicit-stack push is exactly the
        // bug shape this collapse closed. Pushing while `.give` is presented
        // must land on `.give`, even if the destination's "natural home" is
        // `.balance` (e.g. `.currencyInfoForDeposit` opened from inside the
        // give flow's "Add More Cash" path).
        let router = AppRouter()

        router.present(.balance)
        router.push(.currencyInfo(.usdc))
        #expect(router[.balance].count == 1)

        router.present(.give)
        router.push(.currencyInfoForDeposit(.usdc))

        #expect(router[.balance].count == 1, "balance path preserved across swap")
        #expect(router[.give].count == 1, "new push lands on the current sheet's stack")
        #expect(router[.settings].isEmpty)
    }

    @Test("pushAny lands on the currently-presented sheet's stack")
    func pushAny_landsOnPresentedStack() {
        let router = AppRouter()
        router.present(.settings)
        router.pushAny(WithdrawNavigationPath.enterAmount)
        #expect(router[.settings].count == 1)
        #expect(router[.balance].isEmpty)
        #expect(router[.give].isEmpty)
    }

    @Test("pushAny is a no-op when no sheet is presented")
    func pushAny_noopWhenNoSheet() {
        let router = AppRouter()
        router.pushAny(WithdrawNavigationPath.enterAmount)
        #expect(router[.balance].isEmpty)
        #expect(router[.settings].isEmpty)
        #expect(router[.give].isEmpty)
    }

    // MARK: - present / dismissSheet

    @Test("present sets the sheet")
    func present_setsSheet() {
        let router = AppRouter()
        router.present(.balance)
        #expect(router.presentedSheet == .balance)
    }

    @Test("dismissSheet clears the sheet")
    func dismissSheet_clearsSheet() {
        let router = AppRouter()
        router.present(.balance)
        router.dismissSheet()
        #expect(router.presentedSheet == nil)
    }

    @Test("present is idempotent")
    func present_isIdempotent() {
        let router = AppRouter()
        router.present(.balance)
        router.setPath([.currencyInfo(.usdc)], on: .balance)
        router.present(.balance)
        #expect(router.presentedSheet == .balance)
        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdc)))
    }

    @Test("dismissSheet on no-sheet is a no-op")
    func dismissSheet_onNothing_isNoop() {
        let router = AppRouter()
        router.dismissSheet()
        #expect(router.presentedSheet == nil)
    }

    @Test("dismissSheet leaves the path intact for the dismiss-animation snapshot")
    func dismissSheet_leavesPathIntact() {
        let router = AppRouter()
        router.present(.balance)
        router.push(.currencyInfo(.usdc))

        router.dismissSheet()

        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdc)),
                "path should survive dismiss so the closing sheet animates with its current contents")
    }

    @Test("re-presenting a previously-dismissed sheet clears its stack path")
    func present_afterDismiss_clearsPath() {
        let router = AppRouter()
        router.present(.balance)
        router.push(.currencyInfo(.usdc))
        router.dismissSheet()

        router.present(.balance)

        #expect(router[.balance].isEmpty,
                "re-opening after a dismiss must start at root")
    }

    @Test("re-presenting after dismiss + opening another sheet still clears on return")
    func present_afterDismissAndIntermediate_stillClearsOnReturn() {
        let router = AppRouter()
        router.present(.balance)
        router.push(.currencyInfo(.usdc))
        router.dismissSheet()
        router.present(.settings)

        router.present(.balance)

        #expect(router[.balance].isEmpty,
                "the dismissed-marker survives across other presentations")
    }

    @Test("sheet swap (no dismiss between) preserves both stacks' paths")
    func present_swap_preservesPaths() {
        let router = AppRouter()
        router.present(.balance)
        router.push(.currencyInfo(.usdc))
        router.setPath([.settingsMyAccount], on: .settings)

        router.present(.settings)
        router.present(.balance)

        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdc)),
                "swap-back must restore the original path")
        #expect(router[.settings] == AppRouter.navigationPath(.settingsMyAccount),
                "the swapped-from path must survive")
    }

    // MARK: - Destination payload

    @Test(
        "destinations carrying a mint expose its base58 as the log payload",
        arguments: [
            AppRouter.Destination.currencyInfo(.usdc),
            AppRouter.Destination.currencyInfoForDeposit(.usdc),
            AppRouter.Destination.transactionHistory(.usdc),
            AppRouter.Destination.give(.usdc),
            AppRouter.Destination.deposit(.usdc),
        ]
    )
    func destination_payload_returnsMintForKeyedCases(_ destination: AppRouter.Destination) {
        #expect(destination.payload == PublicKey.usdc.base58)
    }

    @Test(
        "payload-free destinations return nil so the log key is omitted",
        arguments: [
            AppRouter.Destination.discoverCurrencies,
            AppRouter.Destination.currencyCreationSummary,
            AppRouter.Destination.currencyCreationWizard,
            AppRouter.Destination.settingsMyAccount,
            AppRouter.Destination.depositCurrencyList,
            AppRouter.Destination.withdraw,
        ]
    )
    func destination_payload_returnsNilForKeylessCases(_ destination: AppRouter.Destination) {
        #expect(destination.payload == nil)
    }
}
