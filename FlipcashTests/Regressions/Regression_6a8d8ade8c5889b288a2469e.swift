//
//  Regression_6a8d8ade8c5889b288a2469e.swift
//  FlipcashTests
//
//  Crash: "No Observable object of type Container found" while the nav bar
//         sized the conversation's principal title item. The app logs showed
//         three taps on one chat row pushing `.tipConversation` three times
//         in the same second, stacking three copies of the chat mid-transition.
//
//  Fix: `AppRouter.push` drops a destination equal to the one it just pushed
//       onto that stack, until anything else changes the stack.
//

import SwiftUI
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Regression: 6a8d8ad – repeated row taps stack the same chat", .bug("6a8d8ade8c5889b288a2469e"))
struct Regression_6a8d8ad {

    @Test("Tapping a chat row three times pushes the chat once")
    func repeatedPush_sameConversation_pushesOnce() {
        let router = AppRouter()
        router.activeTabStack = .tips

        router.push(.tipConversation(.test(1)))
        router.push(.tipConversation(.test(1)))
        router.push(.tipConversation(.test(1)))

        #expect(router[.tips] == AppRouter.navigationPath(.tipConversation(.test(1))))
    }

    @Test("A different destination still pushes on top")
    func push_differentDestination_appends() {
        let router = AppRouter()
        router.activeTabStack = .tips

        router.push(.tipConversation(.test(1)))
        router.push(.tipConversation(.test(2)))

        #expect(router[.tips] == AppRouter.navigationPath(.tipConversation(.test(1)), .tipConversation(.test(2))))
    }

    @Test("After popping back to the list, the same chat opens again")
    func push_afterPop_appendsAgain() {
        let router = AppRouter()
        router.activeTabStack = .tips

        router.push(.tipConversation(.test(1)))
        router.pop(on: .tips)
        router.push(.tipConversation(.test(1)))

        #expect(router[.tips] == AppRouter.navigationPath(.tipConversation(.test(1))))
    }

    @Test("After a swipe-back through the binding, the same chat opens again")
    func push_afterBindingPop_appendsAgain() {
        let router = AppRouter()
        router.activeTabStack = .tips

        router.push(.tipConversation(.test(1)))
        router[.tips] = NavigationPath()
        router.push(.tipConversation(.test(1)))

        #expect(router[.tips] == AppRouter.navigationPath(.tipConversation(.test(1))))
    }

    @Test("A sub-flow push between two identical pushes keeps both")
    func push_afterPushAny_appendsAgain() {
        let router = AppRouter()
        router.activeTabStack = .tips

        router.push(.tipConversation(.test(1)))
        router.pushAny(42)
        router.push(.tipConversation(.test(1)))

        #expect(router[.tips].count == 3)
    }
}
