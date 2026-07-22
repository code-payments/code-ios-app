//
//  AppIntentContext.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// Main-actor-confined bridge from App Intents (which run outside the SwiftUI
/// environment) to the live session. `AppDelegate` points it at the
/// `SessionAuthenticator` at launch; intents and entity queries read through it.
///
/// Everything degrades to "no session": a logged-out or send-disabled state
/// yields no contacts and a `false` `canSend`, so the Send shortcut stays inert
/// until the feature is available.
@MainActor
enum AppIntentContext {

    static var sessionAuthenticator: SessionAuthenticator?

    private static var loggedInContainer: SessionContainer? {
        guard case .loggedIn(let container) = sessionAuthenticator?.state else { return nil }
        return container
    }

    /// Whether the signed-in user can send — gates both the contact query and
    /// the intent. Mirrors `Session.canSend`.
    static var canSend: Bool {
        loggedInContainer?.session.canSend ?? false
    }

    /// On-Flipcash contacts the user can send to, or `[]` when logged out or
    /// send is unavailable. Invite-only (non-Flipcash) contacts are excluded —
    /// they can't receive cash.
    static func sendableContacts() async -> [ResolvedContact] {
        guard canSend, let container = loggedInContainer else { return [] }
        return await RecipientLoader.load(database: container.database).onFlipcash
    }

    static func contact(withID id: String) async -> ResolvedContact? {
        await sendableContacts().first { $0.id == id }
    }

    /// Foregrounds the app on the Send Cash amount entry for `contact`, presented
    /// directly as a sheet (one animation, no chat behind).
    static func openSendFlow(to contact: ResolvedContact) {
        loggedInContainer?.appRouter.present(.sendAmount(.contact(contact)))
    }
}
