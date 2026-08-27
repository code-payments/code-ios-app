//
//  YouTabRoutingTests.swift
//  FlipcashTests
//

import SwiftUI
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("You tab routing")
struct YouTabRoutingTests {

    @Test("the .you stack is a tab stack, not a sheet")
    func youStack_hasNoSheet() {
        #expect(AppRouter.Stack.you.sheet == nil)
        #expect(AppRouter.Stack.you.description == "you")
    }

    @Test("pushing a settings destination while the You tab is active lands on .you")
    func push_onActiveYouTab_landsOnYouStack() {
        let router = AppRouter()
        router.activeTabStack = .you
        router.push(.settingsMyAccount)
        #expect(router[.you] == AppRouter.navigationPath(.settingsMyAccount))
        #expect(router[.balance].isEmpty) // never leaks onto another tab's stack
    }

    @Test("a self tipcard link brings the You tab forward at its root")
    func showOwnTipCard_inTabUI_selectsYouTabAtRoot() {
        let router = AppRouter()
        // Drilled into My Account behind a sheet — where a self link can land.
        router.setPath([.settingsMyAccount], on: .you)
        router.present(.give)

        router.showOwnTipCard()

        #expect(router.requestedTabStack == .you)
        #expect(router.presentedSheet == nil)
        #expect(router[.you].isEmpty) // the card itself, not a pushed screen
    }

    @Test("a repeat self scan is absorbed once the You tab request is in flight")
    func showOwnTipCard_whileRequestPending_doesNotRefire() {
        let router = AppRouter()
        router.showOwnTipCard()
        #expect(router.requestedTabStack == .you)

        // What HomeTabView does on selecting the tab.
        router.requestedTabStack = nil
        router.activeTabStack = .you

        // The scanner keeps decoding the same tipcode until the camera tears down.
        router.showOwnTipCard()
        #expect(router.requestedTabStack == nil, "arriving must not re-request the tab")
    }

    @Test("a self scan from a pushed You-tab screen returns to the card")
    func showOwnTipCard_fromPushedYouScreen_popsToRoot() {
        let router = AppRouter()
        router.activeTabStack = .you
        router.push(.settingsMyAccount)

        router.showOwnTipCard()

        #expect(router[.you].isEmpty)
        #expect(router.requestedTabStack == .you)
    }

    @Test("changing the display name pushes onto the You tab, and saving pops back")
    func changeDisplayName_pushesAndPopsOnYouStack() {
        let router = AppRouter()
        router.activeTabStack = .you
        router.push(.settingsMyAccount)
        router.push(.changeDisplayName)
        #expect(router[.you] == AppRouter.navigationPath(.settingsMyAccount, .changeDisplayName))

        // What `ProfileNameScreen(completion: .back)` runs once the name saves.
        router.popTopmost()
        #expect(router[.you] == AppRouter.navigationPath(.settingsMyAccount))
    }
}
