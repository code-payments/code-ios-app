//
//  AppDelegate.swift
//  Code
//
//  Created by Dima Bart on 2024-10-04.
//

import SwiftUI
import BackgroundTasks
import CodeUI
import FlipchatServices

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    
    private let container = AppContainer()

    // MARK: - Launch -
    
    func applicationDidFinishLaunching(_ application: UIApplication) {
        self.window = UIWindow(frame: UIScreen.main.bounds)
        
        Analytics.initialize()
        
        ErrorReporting.initialize()
        
        setupFonts()
        setupAppearance()
        
        registerBackgroundTask()
        
        assignHost()
    }
    
    private func assignHost() {
        guard let window = window else {
            return
        }
        
        let controller = UIHostingController(
            rootView: ContainerScreen(
                sessionAuthenticator: container.sessionAuthenticator
            )
            .injectingEnvironment(from: container)
        )
        controller.view.backgroundColor = .backgroundMain
        
        window.rootViewController = controller
        window.makeKeyAndVisible()
    }
    
    // MARK: - Background Fetch -
    
    private func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: .bgSync, using: .main) { [weak self] task in
            Task {
                try await self?.performBackgroundRefresh()
            }
        }
    }
    
    private func beginBackgroundTask() throws {
        cancelBackgroundTaskIfNeeded()
        try scheduleBackgroundRefresh()
    }
    
    @discardableResult
    private func performBackgroundRefresh() async throws -> Int {
        trace(.warning, components: "[BGF] Performing background sync.")
        
        try scheduleBackgroundRefresh()
        
        guard case .loggedIn(let state) = container.sessionAuthenticator.state else {
            trace(.failure, components: "[BGF] Skipping, not logged in.")
            return 0
        }
        
        let chatController = state.chatController
        Analytics.backgroundSync()
        
        do {
            return try await chatController.sync()
        } catch {
            return 0
        }
    }
    
    private func scheduleBackgroundRefresh() throws {
        let request = BGAppRefreshTaskRequest(identifier: .bgSync)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 min
        try BGTaskScheduler.shared.submit(request)
        
        trace(.warning, components: "[BGF] Scheduled background sync.")
    }
    
    private func cancelBackgroundTaskIfNeeded() {
        trace(.warning, components: "[BGF] Cancelling background sync.")
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: .bgSync)
    }
    
    // MARK: - Push Notifications -
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        guard case .loggedIn(let state) = container.sessionAuthenticator.state else {
            trace(.failure, components: "APNS: registration failed, not logged in")
            return
        }
        
        state.pushController.didReceiveRemoteNotificationToken(with: deviceToken)
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        trace(.failure, components: "APNS: Push notification registration failed: \(error)")
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any]) async -> UIBackgroundFetchResult {
        trace(.warning, components: "APNS: Received push notification: \(userInfo)")
        return .noData
    }
    
    // MARK: - SwiftUI Scene Phase -
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        trace(.warning)
        guard case .loggedIn(let state) = container.sessionAuthenticator.state else {
            return
        }
        
        state.chatController.sceneDidBecomeActive()
        cancelBackgroundTaskIfNeeded()
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        trace(.warning)
        guard case .loggedIn(let state) = container.sessionAuthenticator.state else {
            return
        }
        
        state.chatController.sceneDidEnterBackground()
        try? beginBackgroundTask()
    }
    
    // MARK: - Appearance -
    
    private func setupFonts() {
        FontBook.registerApplicationFonts()
    }
    
    private func setupAppearance() {
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

extension String {
    static let bgSync = "com.flipchat.background.sync"
}
