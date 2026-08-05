//
//  QuickActionsController.swift
//  Flipcash
//

import UIKit
import FlipcashCore

/// Owns the Home Screen quick actions (long-press the app icon).
///
/// Actions are installed on login and cleared on logout. Taps reuse the existing
/// deep-link pipeline via each action's `url` userInfo (see ``SceneDelegate``).
@MainActor
final class QuickActionsController {

    init() {}

    func configure() {
        UIApplication.shared.shortcutItems = Self.shortcutItems()
    }

    static func clear() {
        UIApplication.shared.shortcutItems = []
    }

    nonisolated static func shortcutItems() -> [UIApplicationShortcutItem] {
        [
            item(type: "discover", title: "Discover", symbol: "binoculars", url: "flipcash://discover"),
            item(type: "give", title: "Cash", symbol: "banknote", url: "flipcash://give"),
            item(type: "wallet", title: "Wallet", symbol: "wallet.bifold", url: "flipcash://balance"),
        ]
    }

    nonisolated private static func item(type: String, title: String, symbol: String, url: String) -> UIApplicationShortcutItem {
        UIApplicationShortcutItem(
            type: "com.flipcash.shortcut.\(type)",
            localizedTitle: title,
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(systemImageName: symbol),
            userInfo: ["url": url as NSString]
        )
    }
}
