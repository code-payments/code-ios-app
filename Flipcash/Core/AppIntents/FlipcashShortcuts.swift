//
//  FlipcashShortcuts.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import AppIntents

/// Surfaces the app's intents to Siri and Spotlight without user setup. Auto-
/// discovered by the system — no Info.plist entry needed.
struct FlipcashShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SendCashIntent(),
            phrases: [
                "Send cash with \(.applicationName)",
                "Send money with \(.applicationName)",
            ],
            shortTitle: "Send Cash",
            systemImageName: "paperplane.circle.fill"
        )
    }
}
