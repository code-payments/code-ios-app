//
//  SettingsRoutingTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash

@MainActor
@Suite("Settings routing")
struct SettingsRoutingTests {

    @Test("Settings and Account Info are owned by the You stack", arguments: [
        AppRouter.Destination.settings,
        AppRouter.Destination.accountInfo,
    ])
    func owningStack(destination: AppRouter.Destination) {
        #expect(destination.owningStack == .you)
    }

    @Test("Pushing Settings from the You tab lands on the You stack")
    func pushLandsOnYou() {
        let router = AppRouter()

        router.activeTabStack = .you
        router.push(.settings)

        #expect(router[.you] == AppRouter.navigationPath(.settings))
    }

    @Test("Log names are stable and carry no payload")
    func logNames() {
        #expect(AppRouter.Destination.settings.description == "settings")
        #expect(AppRouter.Destination.accountInfo.description == "accountInfo")
        #expect(AppRouter.Destination.settings.payload == nil)
        #expect(AppRouter.Destination.accountInfo.payload == nil)
    }
}
