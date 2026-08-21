//
//  ChangeDisplayNameScreen.swift
//  Flipcash
//

import SwiftUI

/// Editing the display name on its own, reached from My Account (node
/// 9277:121893). Hosts the profile-setup name step, which returns here once the
/// name saves instead of carrying on to the tip card.
struct ChangeDisplayNameScreen: View {

    /// The name step reads its text from the environment: profile setup owns
    /// that state at its sheet root so the photo step can read the name back.
    /// A lone edit has no following step, so it owns the state itself, seeded
    /// with the name already on the profile.
    @State private var creationState: ProfileCreationState

    init(currentName: String) {
        let state = ProfileCreationState()
        state.displayName = currentName
        _creationState = State(initialValue: state)
    }

    var body: some View {
        ProfileNameScreen(completion: .back)
            .environment(creationState)
    }
}
