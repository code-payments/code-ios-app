//
//  AppRouterNestedSheetTests.swift
//  FlipcashTests
//
//  Created by Raul Riera on 2026-05-12.
//

import SwiftUI
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("AppRouter Nested Sheets")
struct AppRouterNestedSheetTests {

    private static let mintA: PublicKey = .usdc
    private static let mintB: PublicKey = .usdf

    // MARK: - State model

    @Test("presentedSheets starts empty")
    func presentedSheets_startsEmpty() {
        let router = AppRouter()
        #expect(router.presentedSheets.isEmpty)
        #expect(router.presentedSheet == nil)
        #expect(router.rootSheet == nil)
    }

    @Test("present sets root, topmost == root when no nesting")
    func present_setsRoot() {
        let router = AppRouter()
        router.present(.balance)
        #expect(router.presentedSheets == [.balance])
        #expect(router.presentedSheet == .balance)
        #expect(router.rootSheet == .balance)
    }

    @Test("presentNested appends on top of root")
    func presentNested_appendsOnRoot() {
        let router = AppRouter()
        router.present(.balance)

        router.presentNested(.buy(Self.mintA))

        #expect(router.presentedSheets == [.balance, .buy(Self.mintA)])
        #expect(router.presentedSheet == .buy(Self.mintA))
        #expect(router.rootSheet == .balance)
    }

    @Test("presentNested with empty stack is a no-op")
    func presentNested_onEmpty_isNoop() {
        let router = AppRouter()
        router.presentNested(.buy(Self.mintA))
        #expect(router.presentedSheets.isEmpty)
    }

    @Test("presentNested idempotent when same sheet already on top")
    func presentNested_idempotent_onSameTop() {
        let router = AppRouter()
        router.present(.balance)
        router.presentNested(.buy(Self.mintA))

        router.presentNested(.buy(Self.mintA))

        #expect(router.presentedSheets == [.balance, .buy(Self.mintA)])
    }

    @Test("presentNested same case different payload swaps the top")
    func presentNested_sameCaseDifferentPayload_swaps() {
        let router = AppRouter()
        router.present(.balance)
        router.presentNested(.buy(Self.mintA))
        router.pushAny(BuyFlowPath.phantomEducation(
            mint: Self.mintA,
            amount: ExchangedFiat.compute(onChainAmount: .zero(mint: .usdf), rate: .oneToOne, supplyQuarks: nil)
        ))

        router.presentNested(.buy(Self.mintB))

        // Same case different payload → swap (not stack).
        #expect(router.presentedSheets == [.balance, .buy(Self.mintB)])
        // Displaced sheet's path is cleared because it landed in dismissedSheets
        // and the new value sits in a different SheetPresentation hash bucket.
        // Either way, the new top should be at root of the buy stack via
        // the dismissed-path-clear contract (verified separately).
    }

    @Test("presentNested same case different payload — no prior pushed content — swaps cleanly")
    func presentNested_sameCaseDifferentPayload_noPriorPath_swaps() {
        let router = AppRouter()
        router.present(.balance)
        router.presentNested(.buy(Self.mintA))

        router.presentNested(.buy(Self.mintB))

        #expect(router.presentedSheets == [.balance, .buy(Self.mintB)])
        #expect(router[.buy].isEmpty, "no path was set; the new top should sit at root of the buy stack")
    }

    // MARK: - dismissSheet

    @Test("dismissSheet pops topmost when nested is up")
    func dismissSheet_withNested_popsTopmost() {
        let router = AppRouter()
        router.present(.balance)
        router.presentNested(.buy(Self.mintA))

        router.dismissSheet()

        #expect(router.presentedSheets == [.balance])
        #expect(router.presentedSheet == .balance)
    }

    @Test("dismissSheet pops root when only root remains")
    func dismissSheet_onRootOnly_clearsAll() {
        let router = AppRouter()
        router.present(.balance)

        router.dismissSheet()

        #expect(router.presentedSheets.isEmpty)
        #expect(router.presentedSheet == nil)
    }

    @Test("dismissSheet sequence pops one level at a time")
    func dismissSheet_sequence_popsLevels() {
        let router = AppRouter()
        router.present(.balance)
        router.presentNested(.buy(Self.mintA))

        router.dismissSheet()
        #expect(router.presentedSheets == [.balance])

        router.dismissSheet()
        #expect(router.presentedSheets.isEmpty)
    }

    // MARK: - present semantics with nested up

    @Test("present(.differentRoot) when nested is up clears everything and sets new root")
    func present_differentRoot_clearsAll() {
        let router = AppRouter()
        router.present(.balance)
        router.presentNested(.buy(Self.mintA))

        router.present(.settings)

        #expect(router.presentedSheets == [.settings])
    }

    @Test("present(.sameRoot) when nested is up pops the nested and keeps root")
    func present_sameRoot_popsNestedKeepsRoot() {
        let router = AppRouter()
        router.present(.balance)
        router.push(.currencyInfo(Self.mintA))
        router.presentNested(.buy(Self.mintA))

        router.present(.balance)

        #expect(router.presentedSheets == [.balance])
        // Root path is preserved because root wasn't dismissed.
        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(Self.mintA)))
    }

    @Test("present(.differentRoot) when nested is up clears the new root's stale path")
    func present_differentRoot_clearsNewRootPath() {
        let router = AppRouter()
        router.present(.balance)
        router.push(.currencyInfo(Self.mintA))
        router.dismissSheet()  // .balance now in dismissedSheets

        router.present(.settings)
        router.presentNested(.buy(Self.mintA))

        // Now re-present .balance — should clear its stale path.
        router.present(.balance)

        #expect(router.presentedSheets == [.balance])
        #expect(router[.balance].isEmpty,
                "presenting a previously dismissed root after nesting still clears its path")
    }

    // MARK: - Path clear on reopen at nested level

    @Test("dismissSheet + presentNested(.same) clears the nested sheet's path")
    func dismissNested_thenPresentNestedSame_clearsPath() {
        let router = AppRouter()
        router.present(.balance)
        router.presentNested(.buy(Self.mintA))
        router.pushAny(BuyFlowPath.phantomEducation(
            mint: Self.mintA,
            amount: ExchangedFiat.compute(onChainAmount: .zero(mint: .usdf), rate: .oneToOne, supplyQuarks: nil)
        ))

        router.dismissSheet()  // Pop .buy(mintA); its path is still populated.
        router.presentNested(.buy(Self.mintA))

        #expect(router[.buy].isEmpty,
                "re-opening a dismissed nested sheet must land at root")
    }

    @Test("nested swipe-down + reopen still clears path")
    func dismissNested_thenReopenAfterIntermediate_stillClearsPath() {
        let router = AppRouter()
        router.present(.balance)
        router.presentNested(.buy(Self.mintA))
        router.pushAny(BuyFlowPath.phantomEducation(
            mint: Self.mintA,
            amount: ExchangedFiat.compute(onChainAmount: .zero(mint: .usdf), rate: .oneToOne, supplyQuarks: nil)
        ))
        router.dismissSheet()  // .buy dismissed
        router.dismissSheet()  // .balance dismissed

        router.present(.balance)
        router.presentNested(.buy(Self.mintA))

        #expect(router[.buy].isEmpty)
    }

    // MARK: - dismissAll

    @Test("dismissAll clears every level")
    func dismissAll_clearsEveryLevel() {
        let router = AppRouter()
        router.present(.balance)
        router.presentNested(.buy(Self.mintA))

        router.dismissAll()

        #expect(router.presentedSheets.isEmpty)
        #expect(router.presentedSheet == nil)
    }

    @Test("dismissAll marks every dismissed sheet for path clear on reopen")
    func dismissAll_clearsPathsOnReopen() {
        let router = AppRouter()
        router.present(.balance)
        router.push(.currencyInfo(Self.mintA))
        router.presentNested(.buy(Self.mintA))
        router.pushAny(BuyFlowPath.phantomEducation(
            mint: Self.mintA,
            amount: ExchangedFiat.compute(onChainAmount: .zero(mint: .usdf), rate: .oneToOne, supplyQuarks: nil)
        ))

        router.dismissAll()
        router.present(.balance)
        router.presentNested(.buy(Self.mintA))

        #expect(router[.balance].isEmpty)
        #expect(router[.buy].isEmpty)
    }

    // MARK: - navigate with nested up

    @Test("navigate(to:) when nested is up dismisses nested and sets target root")
    func navigate_dismissesNestedAndSetsRoot() {
        let router = AppRouter()
        router.present(.balance)
        router.presentNested(.buy(Self.mintA))

        router.navigate(to: .settingsApplicationLogs)

        #expect(router.presentedSheets == [.settings])
        #expect(router[.settings] == AppRouter.navigationPath(.settingsApplicationLogs))
    }

    @Test("navigate(to:) on same-root destination while nested is up pops nested")
    func navigate_sameRoot_popsNested() {
        let router = AppRouter()
        router.present(.balance)
        router.push(.currencyInfo(Self.mintA))
        router.presentNested(.buy(Self.mintA))

        router.navigate(to: .currencyInfo(Self.mintB))

        #expect(router.presentedSheets == [.balance])
        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(Self.mintB)))
    }

    // MARK: - Push lands on topmost

    @Test("push lands on the nested sheet's stack when nested is up")
    func push_landsOnNestedStack() {
        let router = AppRouter()
        router.present(.balance)
        router.presentNested(.buy(Self.mintA))

        router.pushAny(BuyFlowPath.phantomEducation(
            mint: Self.mintA,
            amount: ExchangedFiat.compute(onChainAmount: .zero(mint: .usdf), rate: .oneToOne, supplyQuarks: nil)
        ))

        #expect(router[.buy].count == 1, "pushes target the topmost stack")
        #expect(router[.balance].isEmpty, "root stack stays clean")
    }

    @Test("top-level Destination push while .buy is nested lands on .buy stack")
    func push_topLevelDestination_whileBuyNested_landsOnBuyStack() {
        let router = AppRouter()
        router.present(.balance)
        router.presentNested(.buy(Self.mintA))

        router.push(.usdcDepositEducation)
        router.push(.usdcDepositAddress)

        #expect(router[.buy] == AppRouter.navigationPath(.usdcDepositEducation, .usdcDepositAddress))
        #expect(router[.balance].isEmpty, "balance stack stays clean")
    }

    // MARK: - Buy sheet wiring

    @Test(".buy(mint) sheet maps to .buy stack")
    func buySheet_mapsToBuyStack() {
        #expect(AppRouter.SheetPresentation.buy(Self.mintA).stack == .buy)
    }
}
