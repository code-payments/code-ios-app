//
//  SceneDelegate.swift
//  Flipcash
//

import UIKit
import FlipcashCore

private let logger = Logger(label: "flipcash.scene-delegate")

/// Bridges quick-action taps into the existing deep-link pipeline. SwiftUI's
/// `App` lifecycle doesn't forward `UIApplicationShortcutItem` events to
/// `AppDelegate`, so we receive them here, pull the embedded URL out of the
/// shortcut's `userInfo`, and post the same notification the rest of the
/// app's URL handlers already observe.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let shortcut = connectionOptions.shortcutItem {
            postDeepLink(for: shortcut)
        }
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(postDeepLink(for: shortcutItem))
    }

    @discardableResult
    private func postDeepLink(for shortcut: UIApplicationShortcutItem) -> Bool {
        guard let urlString = shortcut.userInfo?["url"] as? String,
              let url = URL(string: urlString) else {
            logger.warning("Quick action missing url userInfo", metadata: ["type": "\(shortcut.type)"])
            return false
        }
        NotificationCenter.default.post(
            name: .shortcutDeepLinkReceived,
            object: nil,
            userInfo: ["url": url]
        )
        return true
    }
}
