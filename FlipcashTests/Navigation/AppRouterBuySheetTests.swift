//
//  AppRouterBuySheetTests.swift
//  FlipcashTests
//
//  Created by Raul Riera on 2026-05-12.
//

import Testing
import FlipcashCore
@testable import Flipcash

@Suite("AppRouter buy nested sheet")
@MainActor
struct AppRouterBuySheetTests {

    @Test("presentNested(.buy(mint)) stacks on .balance")
    func presentNestedBuyOnBalance() {
        let router = AppRouter()
        let mint = PublicKey.usdf
        router.present(.balance)

        router.presentNested(.buy(mint))

        #expect(router.presentedSheets == [.balance, .buy(mint)])
        #expect(router.rootSheet == .balance)
        #expect(router.presentedSheet == .buy(mint))
    }

    @Test(".buy SheetPresentation maps to .buy stack")
    func buySheetMapsToBuyStack() {
        #expect(AppRouter.SheetPresentation.buy(.usdf).stack == .buy)
    }

    @Test("pushAny BuyFlowPath onto the .buy stack appends the value")
    func pushAnyBuyFlowPath() {
        let router = AppRouter()
        let mint = PublicKey.usdf
        router.present(.balance)
        router.presentNested(.buy(mint))

        let pinned = ExchangedFiat.compute(
            onChainAmount: .zero(mint: .usdf),
            rate: .oneToOne,
            supplyQuarks: nil
        )
        router.pushAny(BuyFlowPath.phantomEducation(mint: mint, amount: pinned))

        #expect(router[.buy].count == 1, "pushes target the topmost sheet's stack")
        #expect(router[.balance].isEmpty, "balance stack untouched")
    }
}
