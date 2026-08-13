//
//  AppDelegate.swift
//  Code
//
//  Created by Dima Bart on 2025-05-28.
//

import UIKit
import SwiftUI
import CoreSpotlight
import FlipcashUI
import FlipcashCore

private let logger = Logger(label: "flipcash.app-delegate")

class AppDelegate: UIResponder, UIApplicationDelegate {

    let container: Container

    private var sessionContainer: SessionContainer? {
        container.sessionAuthenticator.loggedInContainer
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

        // Telemetry runs only in Release production launches; DEBUG and any
        // test process stay silent to avoid polluting production dashboards.
        #if !DEBUG
        if !Container.isRunningTests {
            Analytics.initialize()
            ErrorReporting.initialize()
        }
        #endif

        FontBook.registerApplicationFonts()
        setupAppearance()
        RemoteImageCache.install()

        if Container.isRunningUITests {
            UIView.setAnimationsEnabled(false)
            BetaFlags.shared.applyLaunchArgumentOverrides()
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeepLinkNotification(_:)),
            name: .shortcutDeepLinkReceived,
            object: nil
        )

        return true
    }

    /// Routes scene events to ``SceneDelegate``. SwiftUI's `App` lifecycle
    /// uses its own implicit scene delegate by default, swallowing
    /// `windowScene(_:performActionFor:)`; without this method, the
    /// `UISceneDelegateClassName` declared in `Info.plist` is not honored
    /// and quick actions are dropped.
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    // MARK: - Lifecycle -

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background:
            logger.info("scenePhase → background")
            sessionContainer?.session.didEnterBackground()
            container.preferences.appDidEnterBackground()
            sessionContainer?.pushController.clearBadgeCount()
        case .active:
            logger.info("scenePhase → active")
            container.client.warmUpChannel()
            container.flipClient.warmUpChannel()
            sessionContainer?.session.didBecomeActive()
            sessionContainer?.usdcSweepOperation.start()
            sessionContainer?.contactSyncController.didBecomeActive()
            sessionContainer?.conversationController.ensureConnected()
            sessionContainer?.conversationController.catchUpOpenChat()
            Task { await sessionContainer?.blocklistController.refresh() }
            sessionContainer?.pushController.clearBadgeCount()
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    // MARK: - Deep Links -

    func handleOpenURL(url: URL) {
        container.deepLinkController.open(url)
    }

    @objc private func handleDeepLinkNotification(_ notification: Notification) {
        guard let url = notification.userInfo?["url"] as? URL else {
            return
        }

        handleOpenURL(url: url)
    }

    /// Routes a continued `NSUserActivity` — a Spotlight chat tap or a Handoff /
    /// Siri-suggestion of an opened chat — into the deep-link pipeline by
    /// rebuilding the `flipcash://chat/{id}` URL the activity carries.
    func handleContinue(_ activity: NSUserActivity) {
        let chatID: String? = switch activity.activityType {
        case CSSearchableItemActionType:
            activity.userInfo?[CSSearchableItemActivityIdentifier] as? String
        case AppUserActivity.openChat:
            activity.userInfo?[AppUserActivity.chatIDKey] as? String
        default:
            nil
        }

        guard let chatID, let url = URL(string: "flipcash://chat/\(chatID)") else {
            logger.warning("User activity continuation missing chat id", metadata: ["type": "\(activity.activityType)"])
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
            // iOS 26: use the system's default (Liquid Glass) bar background and
            // only override the title fonts. A *transparent* background removes
            // the bar's glass material, so the buttons have no stable bar-glass
            // to composite against and the system repaints their glass during
            // the push transition — that's the flicker as screens push/settle.
            // The buttons are also left to the system (no `backButtonAppearance`)
            // for the same reason.
            let barAppearance = UINavigationBarAppearance()
            barAppearance.configureWithDefaultBackground()
            barAppearance.titleTextAttributes = titleAttributes
            barAppearance.largeTitleTextAttributes = largeAttributes

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

    }
}

// MARK: - UINavigationController -

extension UINavigationController {
    /// Force every pushed screen's back button to the chevron-only (`.minimal`)
    /// display mode. On iOS 26 the default mode carries the previous screen's
    /// title as a back label that re-resolves during the push transition, which
    /// flickers the back arrow as the route settles. Guarded so it only writes
    /// when the value actually changes — `viewWillLayoutSubviews` runs on every
    /// layout pass, and re-setting it each time would itself churn the bar.
    open override func viewWillLayoutSubviews() {
        for viewController in viewControllers
        where viewController.navigationItem.backButtonDisplayMode != .minimal {
            viewController.navigationItem.backButtonDisplayMode = .minimal
        }
    }
}
