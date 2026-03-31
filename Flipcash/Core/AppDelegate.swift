//
//  AppDelegate.swift
//  Code
//
//  Created by Dima Bart on 2025-05-28.
//

import UIKit
import SwiftUI
import FlipcashUI
import FlipcashCore

private let logger = Logger(label: "flipcash.app-delegate")

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    let container = Container()

    private var sessionContainer: SessionContainer? {
        if case .loggedIn(let container) = container.sessionAuthenticator.state {
            return container
        }
        return nil
    }

    // MARK: - Launch -

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        LogStore.bootstrap(middleware: [
            SensitiveKeyRedactor(),
            PatternRedactor(),
        ])

        window = UIWindow(frame: UIScreen.main.bounds)

        let isUITesting = CommandLine.arguments.contains("--ui-testing")

        if !isUITesting {
            Analytics.initialize()
            ErrorReporting.initialize()
        }

        FontBook.registerApplicationFonts()
        setupAppearance()

        if isUITesting {
            UIView.setAnimationsEnabled(false)
        }

        installRootScreen()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeepLinkNotification(_:)),
            name: .pushDeepLinkReceived,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeepLinkNotification(_:)),
            name: .qrDeepLinkReceived,
            object: nil
        )

        return true
    }

    /// Sets up the window with the root ContainerScreen.
    private func installRootScreen() {
        guard let window = window else {
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

    // MARK: - Lifecycle -

    func applicationWillResignActive(_ application: UIApplication) {
        logger.info("applicationWillResignActive")
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        if let sessionContainer {
            sessionContainer.session.didEnterBackground()
        }

        container.preferences.appDidEnterBackground()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        logger.info("applicationWillEnterForeground")

        // Pre-warm the gRPC channel before anything else.
        // After backgrounding the OS kills the TCP socket; this
        // triggers reconnection so the channel is ready by the
        // time streams and RPCs need it.
        container.client.warmUpChannel()

        guard let sessionContainer else { return }

        sessionContainer.session.didBecomeActive()
    }

    // MARK: - Deep Links -

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return handleOpenURL(url: url)
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        guard
            userActivity.activityType == NSUserActivityTypeBrowsingWeb,
            let url = userActivity.webpageURL
        else {
            return false
        }

        return handleOpenURL(url: url)
    }

    private func handleOpenURL(url: URL) -> Bool {
        Analytics.deeplinkOpened(url: url)
        let action = container.deepLinkController.handle(open: url)
        Analytics.deeplinkParsed(action: action, url: url)

        Task {
            try await action?.executeAction()
        }

        return true
    }

    @objc private func handleDeepLinkNotification(_ notification: Notification) {
        guard let url = notification.userInfo?["url"] as? URL else {
            return
        }

        _ = handleOpenURL(url: url)
    }

    // MARK: - Push Notifications -

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        logger.info("Did register for remote notifications", metadata: ["token": "\(deviceToken.hexString())"])

        if let sessionContainer {
            sessionContainer.pushController.didReceiveRemoteNotificationToken(with: deviceToken)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        logger.error("Push notification registration failed: \(error)")
    }

}

// MARK: - Appearance -

private extension AppDelegate {

    func setupAppearance() {
        let largeAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.appDisplayLarge,
            .foregroundColor: UIColor(.textMain),
        ]

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.appTitle,
            .foregroundColor: UIColor(.textMain),
        ]

        let buttonAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.appBarButton,
            .foregroundColor: UIColor(.textMain),
        ]

        let buttonAppearance = UIBarButtonItemAppearance()
        buttonAppearance.normal.titleTextAttributes = buttonAttributes

        let bar = UINavigationBar.appearance()

        bar.largeTitleTextAttributes = largeAttributes
        bar.titleTextAttributes = titleAttributes

        if #available(iOS 26, *) {
            // iOS 26: Transparent background to allow Liquid Glass,
            // but still apply custom title font and button styling
            let barAppearance = UINavigationBarAppearance()
            barAppearance.configureWithTransparentBackground()
            barAppearance.titleTextAttributes = titleAttributes
            barAppearance.largeTitleTextAttributes = largeAttributes
            barAppearance.backButtonAppearance = buttonAppearance

            bar.standardAppearance = barAppearance
            bar.scrollEdgeAppearance = barAppearance
        } else {
            // iOS < 26: Use custom background
            let background = UIImage.solid(color: UIColor(.backgroundMain))
            let barAppearance = UINavigationBarAppearance()
            barAppearance.configureWithOpaqueBackground()
            barAppearance.backgroundImage = background
            barAppearance.shadowImage = background
            barAppearance.titleTextAttributes = titleAttributes
            barAppearance.largeTitleTextAttributes = largeAttributes
            barAppearance.backButtonAppearance = buttonAppearance

            bar.standardAppearance = barAppearance
            bar.scrollEdgeAppearance = barAppearance
            bar.isTranslucent = true
            bar.barStyle = .default
            bar.setBackgroundImage(background, for: .any, barMetrics: .default)
            bar.shadowImage = background
        }

        // Segmented Control
        let segmented = UISegmentedControl.appearance()
        segmented.setTitleTextAttributes([
            .font: UIFont.appTextMedium,
            .foregroundColor: UIColor(.textMain),
        ], for: .normal)
    }
}

// MARK: - UINavigationController -

extension UINavigationController {
    /// Remove the back button in all navigation stacks
    open override func viewWillLayoutSubviews() {
        // Only execute on iOS 18 and below
        if #available(iOS 26, *) {
            return
        }

        for viewController in viewControllers {
            viewController.navigationItem.backButtonDisplayMode = .minimal
        }
    }
}
