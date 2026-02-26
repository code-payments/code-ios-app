//
//  AppDelegate.swift
//  Code
//
//  Created by Dima Bart on 2025-05-28.
//

import UIKit
import FlipcashUI
import FlipcashCore

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    let container = Container()

    // MARK: - Launch -

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        Analytics.initialize()
        ErrorReporting.initialize()
        FontBook.registerApplicationFonts()
        setupAppearance()

        return true
    }

    // MARK: - Scene Configuration -

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    // MARK: - Push Notifications -

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        trace(.success, components: "Did register for remote notifications with token: \(deviceToken.hexString())")

        if case .loggedIn(let sessionContainer) = container.sessionAuthenticator.state {
            sessionContainer.pushController.didReceiveRemoteNotificationToken(with: deviceToken)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        trace(.failure, components: "Push notification registration failed: \(error)")
    }
}

// MARK: - UIApplication -

extension UIApplication {
    static var isInterfaceResetDisabled: Bool = false
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
            // iOS 26: Use minimal configuration to allow liquid glass effect
            let barAppearance = UINavigationBarAppearance()
            barAppearance.configureWithTransparentBackground()
            barAppearance.titleTextAttributes = titleAttributes
            barAppearance.largeTitleTextAttributes = largeAttributes
            barAppearance.backButtonAppearance = buttonAppearance

            bar.standardAppearance = barAppearance
            bar.scrollEdgeAppearance = barAppearance
            bar.isTranslucent = true
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
