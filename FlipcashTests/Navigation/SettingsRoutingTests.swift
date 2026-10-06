//
//  SettingsRoutingTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash

@MainActor
@Suite("Settings routing")
struct SettingsRoutingTests {

    @Test("Settings, Account Info and the profile editors are owned by the You stack", arguments: [
        AppRouter.Destination.settings,
        AppRouter.Destination.accountInfo,
        AppRouter.Destination.editProfile,
        AppRouter.Destination.editBio,
        AppRouter.Destination.changeCoverPicture,
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

    @Test("Popping Edit Bio after a save returns to Edit Profile")
    func savePopsBackToEditProfile() {
        let router = AppRouter()

        router.activeTabStack = .you
        router.push(.editProfile)
        router.push(.editBio)
        #expect(router[.you] == AppRouter.navigationPath(.editProfile, .editBio))

        router.popTopmost()

        #expect(router[.you] == AppRouter.navigationPath(.editProfile))
    }

    @Test("Log names are stable and carry no payload")
    func logNames() {
        #expect(AppRouter.Destination.settings.description == "settings")
        #expect(AppRouter.Destination.accountInfo.description == "accountInfo")
        #expect(AppRouter.Destination.settings.payload == nil)
        #expect(AppRouter.Destination.accountInfo.payload == nil)
    }
}
