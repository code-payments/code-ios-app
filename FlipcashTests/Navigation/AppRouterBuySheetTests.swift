//
//  AppRouterBuySheetTests.swift
//  FlipcashTests
//
//  Created by Raul Riera on 2026-05-12.
//

import Testing
import FlipcashCore
@testable import Flipcash

@Suite("AppRouter buy sheet")
@MainActor
struct AppRouterBuySheetTests {

    @Test("present(.buy(mint)) sets presentedSheet to .buy with the given mint")
    func presentBuySheet() {
        let router = AppRouter()
        let mint = PublicKey.usdf

        router.present(.buy(mint))

        #expect(router.presentedSheet == .buy(mint))
    }

    @Test("present(.buy) targets the .buy stack")
    func buySheetTargetsBuyStack() {
        let router = AppRouter()
        let mint = PublicKey.usdf

        router.present(.buy(mint))

        #expect(router.presentedSheet?.stack == .buy)
    }

    @Test("pushAny BuyFlowPath onto the .buy stack appends the value")
    func pushAnyBuyFlowPath() {
        let router = AppRouter()
        let mint = PublicKey.usdf
        router.present(.buy(mint))

        // Minimal ExchangedFiat with zero on-chain amount against a fixed
        // USD rate, just enough to satisfy BuyFlowPath.phantomEducation.
        let pinned = ExchangedFiat.compute(
            onChainAmount: .zero(mint: .usdf),
            rate: .oneToOne,
            supplyQuarks: nil
        )
        router.pushAny(BuyFlowPath.phantomEducation(mint: mint, amount: pinned))

        #expect(router[.buy].count == 1)
    }
}
