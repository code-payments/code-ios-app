//
//  ProfileTutorialStateTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

/// The checklist is derived from the profile rather than from a dismissal flag,
/// so it must stay silent until a profile has loaded and must disappear on its
/// own once every chore is done.
@Suite
@MainActor
struct ProfileTutorialStateTests {

    private static func state(
        hasProfile: Bool = true,
        name: Bool = true,
        picture: Bool = false,
        minimumTip: Bool = false
    ) -> ProfileTutorialState {
        ProfileTutorialState(
            hasProfile: hasProfile,
            hasDisplayName: name,
            hasProfilePicture: picture,
            hasMinimumTipAmount: minimumTip
        )
    }

    @Test("The checklist is withheld until a profile has loaded")
    func withheldWithoutProfile() {
        #expect(!Self.state(hasProfile: false).isVisible)
    }

    @Test("The checklist shows while any chore is outstanding")
    func shownWhileIncomplete() {
        #expect(Self.state().isVisible)
        #expect(Self.state(name: false, picture: true, minimumTip: true).isVisible)
        #expect(Self.state(picture: true).isVisible)
        #expect(Self.state(minimumTip: true).isVisible)
    }

    @Test("A finished checklist disappears without needing a dismissal")
    func hiddenWhenComplete() {
        let state = Self.state(picture: true, minimumTip: true)
        #expect(state.isComplete)
        #expect(!state.isVisible)
    }

    @Test("Profile fields drive the step completion the card renders")
    func itemsCarryProfileState() {
        let state = Self.state(picture: true)
        #expect(state.items == [
            .displayName(isCompleted: true),
            .profilePicture(isCompleted: true),
            .minimumTipAmount(isCompleted: false),
        ])
    }

    @Test("A name-less profile gets the checklist, with naming it first and outstanding")
    func namelessProfileShowsNameChore() {
        let state = ProfileTutorialState(profile: Profile(displayName: nil, phone: Phone?.none, email: nil))
        #expect(state.isVisible)
        #expect(state.items.first == .displayName(isCompleted: false))
    }
}
