//
//  AppUserActivity.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Identifiers for the `NSUserActivity` the app donates and continues.
/// Shared by the donation site (`ConversationScreen`), the continuation
/// handler (`AppDelegate`), and the scene-root modifiers (`FlipcashApp`).
///
/// The activity type must also be declared in `NSUserActivityTypes` in
/// Info.plist or the system drops the donation.
enum AppUserActivity {
    /// A DM conversation the user opened. Donated for Siri prediction, Handoff,
    /// and Spotlight; carries the chat id under ``chatIDKey``.
    static let openChat = "com.flipcash.app.openChat"

    /// `userInfo` key holding a conversation's `base64URLEncoded` id.
    static let chatIDKey = "conversationID"
}
