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
import Firebase

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    
    let container = Container()
    
    private var hasBeenBackgrounded: Bool = false
    
    // MARK: - Launch -

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        window = UIWindow(frame: UIScreen.main.bounds)
        
        configureFirebase()
        Analytics.initialize()
        ErrorReporting.initialize()
        FontBook.registerApplicationFonts()
        setupAppearance()
        
        assignHost()
        
//        let contentView = ContentView() // Your SwiftUI view
//        let hostingController = UIHostingController(rootView: contentView)
//        window?.rootViewController = hostingController
//        window?.makeKeyAndVisible()
        
        return true
    }
    
    private func assignHost() {
        guard let window = window else {
            return
        }

        let screen = ContainerScreen(container: container)
            .injectingEnvironment(from: container)
        
        let controller = UIHostingController(rootView: screen)
        controller.view.backgroundColor = .backgroundMain
        window.rootViewController = controller
        
        window.makeKeyAndVisible()
        
//        addOverlayIfNeeded()
    }
    
    // MARK: - Lifecycle -
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        hasBeenBackgrounded = true
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
        let action = container.deepLinkController.handle(open: url)
        
        // Calling assignHost() during app launch (when the app
        // hasn't been running) results in a double call making
        // it hang for ~10 seconds. Still uncertain of the exact
        // cause of the problem
        if hasBeenBackgrounded {
            
            // Reset the view in the event that the app handles
            // any deep links to ensure a consistent experience
            assignHost()
        }
        
        Task {
            try await action?.executeAction()
        }
        
        return true
    }
    
    // MARK: - Push Notifications -
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        if case .loggedIn(let container) = container.sessionAuthenticator.state {
//            container.pushController.didReceiveRemoteNotificationToken(with: deviceToken)
        }
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        trace(.failure, components: "Push notification registration failed: \(error)")
    }
}

// MARK: - Firebase -

private extension AppDelegate {
    func configureFirebase() {
        let isRunningPreviews = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        if !isRunningPreviews {
            FirebaseApp.configure()
        }
    }
}

// MARK: - Appearance -

private extension AppDelegate {
    
    func setupAppearance() {
        let largeAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.appDisplayLarge,
            .foregroundColor: UIColor.textMain,
        ]
                              
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.appTitle,
            .foregroundColor: UIColor.textMain,
        ]
        
        let buttonAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.appBarButton,
            .foregroundColor: UIColor.textMain,
        ]
        
        let buttonAppearance = UIBarButtonItemAppearance()
        buttonAppearance.normal.titleTextAttributes = buttonAttributes
                              
        let bar = UINavigationBar.appearance()
        
        bar.largeTitleTextAttributes = largeAttributes
        bar.titleTextAttributes = titleAttributes
        
        let background = UIImage.solid(color: .backgroundMain)
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
        
//        let tableView = UITableView.appearance()
//        tableView.backgroundColor = UIColor.backgroundMain
//        tableView.separatorStyle = .singleLine
//        tableView.separatorInset = UIEdgeInsets(top: 0.0, left: 20.0, bottom: 0.0, right: 0.0)
//        tableView.separatorColor = .rowSeparator
//        tableView.showsVerticalScrollIndicator = false
//        tableView.showsHorizontalScrollIndicator = false
//
//        let selectionView = UIView()
//        selectionView.backgroundColor = UIColor.white.withAlphaComponent(0.1)
//
//        let textView = UITextView.appearance()
//        textView.backgroundColor = .clear
//
//        let scrollView = UIScrollView.appearance()
//        scrollView.keyboardDismissMode = .onDrag
    }
}

// MARK: - UINavigationController -

extension UINavigationController {
    
    /// Remove the back button in all navigation stacks
    open override func viewWillLayoutSubviews() {
        navigationBar.topItem?.backBarButtonItem = UIBarButtonItem(
            title: "",
            style: .plain,
            target: nil,
            action: nil
        )
    }
}
