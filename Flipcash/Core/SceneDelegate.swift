//
//  SceneDelegate.swift
//  Flipcash
//

import UIKit
import FlipcashCore

private let logger = Logger(label: "flipcash.scene-delegate")

/// Bridges quick-action taps and incoming links into the existing deep-link
/// pipeline. SwiftUI's `App` lifecycle doesn't forward `UIApplicationShortcutItem`
/// events to `AppDelegate`, so we receive them here, pull the embedded URL out
/// of the shortcut's `userInfo`, and post the same notification the rest of the
/// app's URL handlers already observe.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let shortcut = connectionOptions.shortcutItem {
            postDeepLink(for: shortcut)
        }
        let webURL = connectionOptions.userActivities.first {
            $0.activityType == NSUserActivityTypeBrowsingWeb
        }?.webpageURL
        if let url = webURL ?? connectionOptions.urlContexts.first?.url {
            postLink(url, source: "launch")
        }
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else {
            return
        }
        postLink(url, source: "continue")
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else {
            return
        }
        postLink(url, source: "openURL")
    }

    /// Posts a link iOS handed the scene into the deep-link pipeline.
    ///
    /// SwiftUI is meant to forward these through `onOpenURL`, but with this
    /// delegate installed it can drop them on device: a Camera scan of a
    /// universal link opened the app, cold or running, with no `onOpenURL`
    /// call. `DeepLinkController` ignores the copy SwiftUI delivers when it
    /// does forward one.
    private func postLink(_ url: URL, source: String) {
        logger.info("Scene received link", metadata: ["source": "\(source)"])
        NotificationCenter.default.post(
            name: .sceneDeepLinkReceived,
            object: nil,
            userInfo: ["url": url]
        )
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
