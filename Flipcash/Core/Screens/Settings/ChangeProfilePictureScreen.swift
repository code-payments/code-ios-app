//
//  ChangeProfilePictureScreen.swift
//  Flipcash
//

import SwiftUI

/// Changing the profile picture on its own, reached from My Account and from
/// the You tab's "Finish Your Profile" checklist (node 9541:10186). Hosts the
/// profile-setup photo step, which returns here once the photo uploads instead
/// of carrying on to the tip card.
struct ChangeProfilePictureScreen: View {

    /// The photo step reads the name from the environment: profile setup owns
    /// that state at its sheet root. A lone edit has no preceding step, so it
    /// owns the state itself, seeded with the name already on the profile.
    @State private var creationState: ProfileCreationState

    init(currentName: String) {
        let state = ProfileCreationState()
        state.displayName = currentName
        _creationState = State(initialValue: state)
    }

    var body: some View {
        ProfilePhotoScreen(completion: .back)
            .environment(creationState)
    }
}
