//
//  AppRouterBuySheetTests.swift
//  FlipcashTests
//
//  Created by Raul Riera on 2026-05-12.
//

import Testing
import FlipcashCore
@testable import Flipcash

@Suite("AppRouter buy push")
@MainActor
struct AppRouterBuySheetTests {

    @Test("push(.buyAmount(mint)) appends to the balance stack")
    func pushBuyAmount() {
        let router = AppRouter()
        let mint = PublicKey.usdf
        router.present(.balance)

        router.push(.buyAmount(mint))

        #expect(router[.balance].count == 1)
    }

    @Test(".buyAmount destination targets the balance stack")
    func buyAmountTargetsBalanceStack() {
        #expect(AppRouter.Destination.buyAmount(.usdf).owningStack == .balance)
    }

    @Test("pushAny BuyFlowPath onto the balance stack appends the value")
    func pushAnyBuyFlowPath() {
        let router = AppRouter()
        let mint = PublicKey.usdf
        router.present(.balance)
        router.push(.buyAmount(mint))

        // Minimal ExchangedFiat with zero on-chain amount against a fixed
        // USD rate, just enough to satisfy BuyFlowPath.phantomEducation.
        let pinned = ExchangedFiat.compute(
            onChainAmount: .zero(mint: .usdf),
            rate: .oneToOne,
            supplyQuarks: nil
        )
        router.pushAny(BuyFlowPath.phantomEducation(mint: mint, amount: pinned))

        // buyAmount + phantomEducation
        #expect(router[.balance].count == 2)
    }
}
