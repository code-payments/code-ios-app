//
//  SwitchAccountSheetTests.swift
//  FlipcashTests
//

import SwiftUI
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Switch Account sheet")
struct SwitchAccountSheetTests {

    @Test("the sheet and its stack map to each other")
    func switchAccount_sheetAndStackAreInverses() {
        #expect(AppRouter.SheetPresentation.switchAccount.stack == .switchAccount)
        #expect(AppRouter.Stack.switchAccount.sheet == .switchAccount)
        #expect(AppRouter.SheetPresentation.switchAccount.caseKind == .switchAccount)
        #expect(AppRouter.SheetPresentation.switchAccount.description == "switchAccount")
        #expect(AppRouter.Stack.switchAccount.description == "switchAccount")
    }

    @Test("the switcher is a sheet, not a tab — nothing in the tab bar hosts it")
    func switchAccount_isNotTabHosted() {
        #expect(AppRouter.Stack.switchAccount.isTabHosted == false)
        #expect(HomeTab.allCases.allSatisfy { $0.pushStack != .switchAccount })
    }

    @Test("a long press from a tab presents the switcher as the root sheet")
    func present_fromTab_becomesRootSheet() {
        let router = AppRouter()
        router.activeTabStack = .you

        router.present(.switchAccount)

        #expect(router.rootSheet == .switchAccount)
        #expect(router.presentedSheet == .switchAccount)
        #expect(router[.switchAccount].isEmpty)
    }

    @Test("closing the switcher leaves the tab where it was")
    func dismiss_returnsToTab() {
        let router = AppRouter()
        router.activeTabStack = .you
        router.push(.settingsMyAccount)
        router.present(.switchAccount)

        router.dismissSheet()

        #expect(router.presentedSheet == nil)
        #expect(router.activeTabStack == .you)
        #expect(router[.you] == AppRouter.navigationPath(.settingsMyAccount))
    }

    @Test("a self tipcard scan dismisses the switcher on its way to the You tab")
    func showOwnTipCard_dismissesSwitcher() {
        let router = AppRouter()
        router.present(.switchAccount)

        router.showOwnTipCard()

        #expect(router.presentedSheet == nil)
        #expect(router.requestedTabStack == .you)
    }
}
