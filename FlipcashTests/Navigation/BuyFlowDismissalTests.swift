//
//  BuyFlowDismissalTests.swift
//  FlipcashTests
//

import SwiftUI
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Buy Flow Dismissal")
struct BuyFlowDismissalTests {

    @Test("Finishing a buy launched from a gated chat returns to the chat")
    func finishPushedBuy_fromChat_returnsToChat() {
        let router = AppRouter()
        router.activeTabStack = .tips
        router.push(.tipConversation(.test(1)))
        router.push(.buyCurrency(.usdc))
        let launch = router.positionBeneathTopmost()
        router.pushAny(AppRouter.Destination.transactionHistory(.usdc))

        BuyAmountScreen.finishPushedBuy(router: router, returningTo: launch)

        #expect(router[.tips] == AppRouter.navigationPath(.tipConversation(.test(1))))
    }

    @Test("Finishing a buy launched from a pushed token screen returns to that screen")
    func finishPushedBuy_fromPushedCurrencyInfo_returnsToIt() {
        let router = AppRouter()
        router.activeTabStack = .balance
        router.push(.currencyInfo(.usdc))
        router.push(.buyCurrency(.usdc))
        let launch = router.positionBeneathTopmost()

        BuyAmountScreen.finishPushedBuy(router: router, returningTo: launch)

        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdc)))
        #expect(router.requestedCardDismiss == 0)
    }

    @Test("Finishing a buy launched from the wallet's expanded card lands on the wallet")
    func finishPushedBuy_fromExpandedCard_dismissesCard() {
        let router = AppRouter()
        router.activeTabStack = .balance
        router.push(.buyCurrency(.usdc))
        let launch = router.positionBeneathTopmost()

        BuyAmountScreen.finishPushedBuy(router: router, returningTo: launch)

        #expect(router[.balance].isEmpty)
        #expect(router.requestedCardDismiss == 1)
    }
}
