//
//  AppRouterScreenNameTests.swift
//  FlipcashTests
//

import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("AppRouter.currentScreenName")
struct AppRouterScreenNameTests {

    @Test("Returns 'Scan' when no sheet is presented")
    func currentScreenName_noSheet_returnsScan() {
        let router = AppRouter()
        #expect(router.currentScreenName == "Scan")
    }

    @Test("Returns the active sheet's analytics name")
    func currentScreenName_balancePresented_returnsBalance() {
        let router = AppRouter()
        router.present(.balance)
        #expect(router.currentScreenName == "Balance")
    }

    @Test("Returns the topmost (nested) sheet, not the root")
    func currentScreenName_nestedSheet_returnsTopmost() {
        let router = AppRouter()
        router.present(.balance)
        router.presentNested(.buy(.usdc))
        #expect(router.currentScreenName == "Buy")
    }

    @Test("Returns 'Scan' again after dismissing all sheets")
    func currentScreenName_afterDismissAll_returnsScan() {
        let router = AppRouter()
        router.present(.settings)
        router.dismissAll()
        #expect(router.currentScreenName == "Scan")
    }
}
