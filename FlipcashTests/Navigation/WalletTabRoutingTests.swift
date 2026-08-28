//
//  WalletTabRoutingTests.swift
//  FlipcashTests
//

import SwiftUI
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Wallet tab routing")
struct WalletTabRoutingTests {

    @Test("putting a grabbed bill in the wallet brings the Wallet tab forward at its root")
    func showWallet_selectsBalanceTabAtRoot() {
        let router = AppRouter()
        // Scanning happens on another tab, and a cash link can arrive over a sheet.
        router.activeTabStack = .tips
        router.setPath([.discoverCurrencies], on: .balance)
        router.present(.give)

        router.showWallet()

        #expect(router.requestedTabStack == .balance)
        #expect(router.presentedSheet == nil)
        #expect(router[.balance].isEmpty)
    }

    @Test("an expanded token card is closed, so nothing covers the balance")
    func showWallet_closesExpandedCard() {
        let router = AppRouter()
        let before = router.requestedCardDismiss

        router.showWallet()

        #expect(router.requestedCardDismiss == before &+ 1)
    }

    @Test("a second deposit while the tab request is in flight does not re-request it")
    func showWallet_whileRequestPending_doesNotRefire() {
        let router = AppRouter()
        router.showWallet()
        #expect(router.requestedTabStack == .balance)

        // What HomeTabView does on selecting the tab.
        router.requestedTabStack = nil
        router.activeTabStack = .balance

        router.showWallet()
        #expect(router.requestedTabStack == nil, "arriving must not re-request the tab")
    }

    @Test("a deposit grabbed from a pushed wallet screen returns to the wallet root")
    func showWallet_fromPushedBalanceScreen_popsToRoot() {
        let router = AppRouter()
        router.activeTabStack = .balance
        router.push(.currencyInfo(.usdc))

        router.showWallet()

        #expect(router[.balance].isEmpty)
        #expect(router.requestedTabStack == .balance)
    }
}
