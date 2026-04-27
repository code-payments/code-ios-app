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
        router.push(.discoverCurrencies, on: .balance)
        #expect(router[.balance] == AppRouter.navigationPath(.discoverCurrencies))
    }

    @Test("push appends in order across multiple calls")
    func push_appendsInOrder() {
        let router = AppRouter()
        router.push(.currencyInfo(.usdc), on: .balance)
        router.push(.transactionHistory(.usdc), on: .balance)
        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdc), .transactionHistory(.usdc)))
    }

    @Test("pop removes the top destination")
    func pop_removesTop() {
        let router = AppRouter()
        router.push(.currencyInfo(.usdc), on: .balance)
        router.push(.transactionHistory(.usdc), on: .balance)
        router.pop(on: .balance)
        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdc)))
    }

    @Test("pop on empty stack is a no-op")
    func pop_onEmpty_isNoop() {
        let router = AppRouter()
        router.pop(on: .balance)
        #expect(router[.balance].isEmpty)
    }

    @Test("popToRoot clears the stack")
    func popToRoot_clearsStack() {
        let router = AppRouter()
        router.push(.currencyInfo(.usdc), on: .balance)
        router.push(.transactionHistory(.usdc), on: .balance)
        router.popToRoot(on: .balance)
        #expect(router[.balance].isEmpty)
    }

    @Test("popLast removes the requested number of items")
    func popLast_removesCount() {
        let router = AppRouter()
        router.push(.currencyInfo(.usdc), on: .balance)
        router.push(.transactionHistory(.usdc), on: .balance)
        router.push(.discoverCurrencies, on: .balance)
        router.popLast(2, on: .balance)
        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdc)))
    }

    @Test("popLast clamps to available depth")
    func popLast_clampsToDepth() {
        let router = AppRouter()
        router.push(.currencyInfo(.usdc), on: .balance)
        router.popLast(10, on: .balance)
        #expect(router[.balance].isEmpty)
    }

    @Test("setPath replaces the entire path")
    func setPath_replacesPath() {
        let router = AppRouter()
        router.push(.currencyInfo(.usdc), on: .balance)
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
        router.push(.withdraw, on: .settings)
        router.pushAny(WithdrawNavigationPath.enterAmount, on: .settings)
        #expect(router[.settings].count == 2)
    }

    @Test("paths on different stacks are independent")
    func stacks_areIndependent() {
        let router = AppRouter()
        router.push(.currencyInfo(.usdc), on: .balance)
        router.push(.settingsMyAccount, on: .settings)
        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdc)))
        #expect(router[.settings] == AppRouter.navigationPath(.settingsMyAccount))
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
}
