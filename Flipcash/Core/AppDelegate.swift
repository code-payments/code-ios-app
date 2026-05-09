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

class AppDelegate: UIResponder, UIApplicationDelegate {

    let container: Container

    private var inFlightDeepLinks: Set<URL> = []

    private var sessionContainer: SessionContainer? {
        if case .loggedIn(let container) = container.sessionAuthenticator.state {
            return container
        }
        return nil
    }

    // MARK: - Init -

    override init() {
        // Bootstrap logging before constructing Container so every Logger
        // in the dependency tree binds to FlipcashLogHandler. Constructing
        // Container first would let early loggers (e.g. WalletConnection)
        // capture swift-log's default StreamLogHandler permanently.
        LogStore.bootstrap(middleware: [
            SensitiveKeyRedactor(),
            PatternRedactor(),
        ])
        self.container = Container()
        super.init()
    }

    // MARK: - Launch -

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

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

    // MARK: - Lifecycle -

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background:
            logger.info("scenePhase → background")
            sessionContainer?.session.didEnterBackground()
            container.preferences.appDidEnterBackground()
        case .active:
            logger.info("scenePhase → active")
            container.client.warmUpChannel()
            container.flipClient.warmUpChannel()
            sessionContainer?.session.didBecomeActive()
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    // MARK: - Deep Links -

    func handleOpenURL(url: URL) {
        // Drop duplicate in-flight deliveries: a concurrent second claim is
        // rejected server-side as stale state and surfaces as a false error
        // after the first claim has already succeeded.
        guard inFlightDeepLinks.insert(url).inserted else {
            logger.info("Ignoring duplicate deep link", metadata: ["url": "\(url.sanitizedForAnalytics)"])
            return
        }

        Analytics.deeplinkOpened(url: url)
        let action = container.deepLinkController.handle(open: url)
        Analytics.deeplinkParsed(action: action, url: url)

        Task {
            defer { self.inFlightDeepLinks.remove(url) }
            try await action?.executeAction()
        }
    }

    @objc private func handleDeepLinkNotification(_ notification: Notification) {
        guard let url = notification.userInfo?["url"] as? URL else {
            return
        }

        handleOpenURL(url: url)
    }

    // MARK: - Push Notifications -

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        logger.info("Did register for remote notifications", metadata: ["token": "\(deviceToken.hexString())"])

        if let sessionContainer {
            sessionContainer.pushController.didReceiveRemoteNotificationToken(with: deviceToken)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        logger.error("Push notification registration failed", metadata: ["error": "\(error)"])
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
