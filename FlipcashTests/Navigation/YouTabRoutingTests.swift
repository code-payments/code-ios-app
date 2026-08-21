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
        #expect(router[.settings].isEmpty) // never leaks onto the Settings sheet's stack
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
