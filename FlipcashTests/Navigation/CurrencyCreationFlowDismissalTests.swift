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

    /// Opens the flow on `stack` over `base` the way the app does: the summary is pushed, records
    /// where it was launched as it first appears, then pushes the wizard.
    private func routerInCreationFlow(
        on stack: AppRouter.Stack = .balance,
        over base: [AppRouter.Destination] = []
    ) -> (AppRouter, CurrencyCreationState) {
        let router = AppRouter()
        let state = CurrencyCreationState()
        router.activeTabStack = stack
        router.setPath(base, on: stack)
        router.push(.currencyCreationSummary)
        CurrencyCreationSummaryScreen.beginCreation(state, router: router)
        router.push(.currencyCreationWizard)
        return (router, state)
    }

    @Test("Finishing the launch cover pops the creation flow off the Wallet stack")
    func dismissCreationFlow_popsHostStack() {
        let (router, state) = routerInCreationFlow()

        CurrencyCreationWizardScreen.dismissCreationFlow(router: router, launchedFrom: state.launchedFrom)

        #expect(router[.balance].isEmpty, "the wizard must not stay mounted under the dismissed cover")
    }

    @Test("Unwinds even though the cover hid the tab host and cleared the active stack")
    func dismissCreationFlow_withoutActiveTabStack_popsHostStack() {
        let (router, state) = routerInCreationFlow()
        // `HomeTabView.onDisappear` clears this while the fullScreenCover is up.
        router.activeTabStack = nil

        CurrencyCreationWizardScreen.dismissCreationFlow(router: router, launchedFrom: state.launchedFrom)

        #expect(router[.balance].isEmpty, "the unwind must not depend on the tab host still being mounted")
    }

    @Test("A flow opened from Settings unwinds to Settings and leaves the Wallet stack alone")
    func dismissCreationFlow_fromSettings_returnsToSettings() {
        let (router, state) = routerInCreationFlow(on: .you, over: [.settings])
        router.setPath([.walletCurrencies], on: .balance)
        router.activeTabStack = nil

        CurrencyCreationWizardScreen.dismissCreationFlow(router: router, launchedFrom: state.launchedFrom)

        var settings = NavigationPath()
        settings.append(AppRouter.Destination.settings)
        #expect(router[.you] == settings, "the summary and wizard come off the You stack, Settings stays")
        #expect(router[.balance].count == 1, "the Wallet stack was never part of the flow")
    }

    @Test("With no recorded launch, the flow still pops the Wallet stack to its root")
    func dismissCreationFlow_withoutLaunchPosition_popsWalletStack() {
        let router = AppRouter()
        router.activeTabStack = .balance
        router.push(.currencyCreationSummary)
        router.push(.currencyCreationWizard)
        router.activeTabStack = nil

        CurrencyCreationWizardScreen.dismissCreationFlow(router: router, launchedFrom: nil)

        #expect(router[.balance].isEmpty)
    }
}
