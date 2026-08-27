//
//  ProfileTutorialStateTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import Flipcash

/// The checklist is derived from the profile rather than from a dismissal flag,
/// so it must stay silent until a profile has loaded and must disappear on its
/// own once both chores are done.
@Suite
@MainActor
struct ProfileTutorialStateTests {

    private static func state(
        hasProfile: Bool = true,
        picture: Bool = false,
        minimumTip: Bool = false
    ) -> ProfileTutorialState {
        ProfileTutorialState(
            hasProfile: hasProfile,
            hasProfilePicture: picture,
            hasMinimumTipAmount: minimumTip
        )
    }

    @Test("The checklist is withheld until a profile has loaded")
    func withheldWithoutProfile() {
        #expect(!Self.state(hasProfile: false).isVisible)
    }

    @Test("The checklist shows while either chore is outstanding")
    func shownWhileIncomplete() {
        #expect(Self.state().isVisible)
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
            .profilePicture(isCompleted: true),
            .minimumTipAmount(isCompleted: false),
        ])
    }
}
