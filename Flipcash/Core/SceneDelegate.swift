//
//  SceneDelegate.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-02-26.
//

import UIKit
import SwiftUI
import FlipcashUI
import FlipcashCore

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    private var resetInterval: TimeInterval = 60.0
    private var lastActiveDate: Date?

    private var hasBeenBackgrounded: Bool = false

    private var appDelegate: AppDelegate {
        UIApplication.shared.delegate as! AppDelegate
    }

    private var container: Container {
        appDelegate.container
    }

    private var sessionContainer: SessionContainer? {
        if case .loggedIn(let container) = container.sessionAuthenticator.state {
            return container
        }
        return nil
    }

    // MARK: - Scene Lifecycle -

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else {
            return
        }

        let window = UIWindow(windowScene: windowScene)
        self.window = window

        assignHost()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePushDeepLinkNotification(_:)),
            name: .pushDeepLinkReceived,
            object: nil
        )

        // Handle cold-launch URL deep links
        if let urlContext = connectionOptions.urlContexts.first {
            _ = handleOpenURL(url: urlContext.url)
        }

        // Handle cold-launch universal links
        if let userActivity = connectionOptions.userActivities.first(where: { $0.activityType == NSUserActivityTypeBrowsingWeb }),
           let url = userActivity.webpageURL {
            _ = handleOpenURL(url: url)
        }
    }

    // MARK: - Lifecycle -

    func sceneWillResignActive(_ scene: UIScene) {
        trace(.warning)
        lastActiveDate = .now
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        hasBeenBackgrounded = true

        if let sessionContainer {
            sessionContainer.session.didEnterBackground()
        }

        container.preferences.appDidEnterBackground()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        trace(.warning)

        if let _ = sessionContainer { // Logged in
            if !UIApplication.isInterfaceResetDisabled {
                if let interval = secondsSinceLastActive(), interval > resetInterval {
                    trace(.warning, components: "Resetting interface...")
                    assignHost()
                } else {
                    // No reset needed
                }
            } else {
                trace(.warning, components: "Interface reset disabled.")
            }

        } else { // Logged out
            // No action needed
        }
    }

    // MARK: - Deep Links -

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else {
            return
        }

        _ = handleOpenURL(url: url)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard
            userActivity.activityType == NSUserActivityTypeBrowsingWeb,
            let url = userActivity.webpageURL
        else {
            return
        }

        _ = handleOpenURL(url: url)
    }

    // MARK: - Private -

    private func assignHost() {
        guard let window else {
            return
        }

        let screen = ContainerScreen(container: container)
            .injectingEnvironment(from: container)
            .colorScheme(.dark)
            .tint(Color.textMain)

        let controller = UIHostingController(rootView: screen)
        controller.view.backgroundColor = UIColor(.backgroundMain)
        window.rootViewController = controller
        window.overrideUserInterfaceStyle = .dark

        window.makeKeyAndVisible()
    }

    private func handleOpenURL(url: URL) -> Bool {
        let action = container.deepLinkController.handle(open: url)

        // Calling assignHost() during app launch (when the app
        // hasn't been running) results in a double call making
        // it hang for ~10 seconds. Still uncertain of the exact
        // cause of the problem
        if hasBeenBackgrounded && action?.preventUserInterfaceReset == false {

            // Reset the view in the event that the app handles
            // any deep links to ensure a consistent experience
            assignHost()
        }

        Task {
            try await action?.executeAction()
        }

        return true
    }

    @objc private func handlePushDeepLinkNotification(_ notification: Notification) {
        guard let url = notification.userInfo?["url"] as? URL else {
            return
        }

        _ = handleOpenURL(url: url)
    }

    private func secondsSinceLastActive() -> TimeInterval? {
        guard let lastActiveDate else {
            return nil
        }

        return Date.now.timeIntervalSince1970 - lastActiveDate.timeIntervalSince1970
    }
}
