//
//  CurrencyCreationFlowDismissalTests.swift
//  FlipcashTests
//

import SwiftUI
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Currency Creation Flow Dismissal")
struct CurrencyCreationFlowDismissalTests {

    /// Pushes the flow the way the Wallet tile does: summary, then wizard.
    private func routerInCreationFlow() -> AppRouter {
        let router = AppRouter()
        router.activeTabStack = .balance
        router.push(.currencyCreationSummary)
        router.push(.currencyCreationWizard)
        return router
    }

    @Test("Finishing the launch cover pops the creation flow off the Wallet stack")
    func dismissCreationFlow_popsHostStack() {
        let router = routerInCreationFlow()

        CurrencyCreationWizardScreen.dismissCreationFlow(router: router)

        #expect(router[.balance].isEmpty, "the wizard must not stay mounted under the dismissed cover")
    }

    @Test("Unwinds even though the cover hid the tab host and cleared the active stack")
    func dismissCreationFlow_withoutActiveTabStack_popsHostStack() {
        let router = routerInCreationFlow()
        // `HomeTabView.onDisappear` clears this while the fullScreenCover is up.
        router.activeTabStack = nil

        CurrencyCreationWizardScreen.dismissCreationFlow(router: router)

        #expect(router[.balance].isEmpty, "the unwind must not depend on the tab host still being mounted")
    }
}
