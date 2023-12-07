//
//  AppDelegate.swift
//  Code
//
//  Created by Dima Bart on 2020-12-17.
//

import SwiftUI
import UIKit
import CodeServices
import CodeUI
import BackgroundTasks
import CodeAPI

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    
    private var coverController: UIViewController?
    
    private var resetInterval: TimeInterval = 60.0
    private var lastActiveDate: Date?
    
    let appContainer = AppContainer()
    
    private var backgroundTaskID: UIBackgroundTaskIdentifier?
    
    private var hasBeenBackgrounded: Bool = false
    
    // MARK: - Application Launch -
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        self.window = UIWindow(frame: UIScreen.main.bounds)
        
        trace(.warning, components: "Background refresh status: \(UIApplication.shared.backgroundRefreshStatus == .available ? "ON" : "OFF")")
        
        print(Environment.current.asciiDescription)
        
        // Setup Firebase, Crashlytics, Mixpanel, etc.
        Analytics.initialize()
        
        // Setup bugsnag, etc.
        ErrorReporting.initialize()
        
        setupFonts()
        setupAppearance()
        
        assignHost()
        
        createOverlay()
        addOverlayIfNeeded()
        fadeOutOverlay(delay: 0.3)
        
        return true
    }
    
    private func assignHost() {
        guard let window = window else {
            return
        }

        let viewModel  = ContainerViewModel(container: appContainer)
        let screen     = appContainer.injectingEnvironment(into: ContainerScreen(viewModel: viewModel))
        let controller = UIHostingController(rootView: screen)
        controller.view.backgroundColor = .backgroundMain
        
        window.rootViewController = controller
        window.makeKeyAndVisible()
        
        addOverlayIfNeeded()
    }
    
    // MARK: - Push Notifications -
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        appContainer.pushController.didReceiveRemoteNotificationToken(with: deviceToken)
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        trace(.failure, components: "Push notification registration failed: \(error)")
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any]) async -> UIBackgroundFetchResult {
        trace(.warning, components: "Push received: \(userInfo)")
        
        guard 
            let chatTitle = userInfo["chat_title"] as? String,
            let messageContent = userInfo["message_content"] as? String
        else {
            return .noData
        }
        
        guard let messageData = Data(base64Encoded: messageContent, options: .ignoreUnknownCharacters) else {
            return .noData
        }
        
        guard
            let rawContent = try? Code_Chat_V1_Content(serializedData: messageData),
            let content = Chat.Content(rawContent)?.localizedText
        else {
            trace(.failure, components: "Failed to parse push data.")
            return .noData
        }
        
        scheduleNotification(title: chatTitle.localizedStringByKey, body: content)
        
        return .newData
    }
    
    private func scheduleNotification(title: String, body: String) {
        let content   = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = UNNotificationSound.default

        let identifier = UUID().uuidString
        let trigger    = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request    = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        Task {
            try await UNUserNotificationCenter.current().add(request)
        }
    }
    
    // MARK: - Activity -
    
    func applicationWillResignActive(_ application: UIApplication) {
        trace(.warning)
        lastActiveDate = .now()
        
        beginBackgroundTask()
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        hasBeenBackgrounded = true
        
        trace(.warning)
        createOverlay()
        addOverlayIfNeeded()
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        trace(.warning)
        if case .loggedOut = appContainer.sessionAuthenticator.state {
            destroyOverlay()
        } else {
            if let interval = computeTimeIntervalSinceLastActive(), interval > resetInterval, !UIApplication.shouldPauseInterfaceReset {
                trace(.warning, components: "Resetting interface...")
                assignHost()
                fadeOutOverlay(delay: 0.4)
            } else {
                fadeOutOverlay(delay: 0.3)
            }
        }
        
        validateSession()
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        cancelBackgroundTaskIfNeeded()
    }
    
    private func computeTimeIntervalSinceLastActive() -> TimeInterval? {
        guard let lastActiveDate = lastActiveDate else {
            return nil
        }

        return Date.now().timeIntervalSince1970 - lastActiveDate.timeIntervalSince1970
    }
    
    private func validateSession() {
        appContainer.sessionAuthenticator.validateInvitationStatus()
    }
    
    // MARK: - Background Task -
    
    private func beginBackgroundTask() {
        cancelBackgroundTaskIfNeeded()
        
        trace(.warning, components: "Starting background task...")
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "com.code.backgroundTask") { [weak self] in
            self?.cancelBackgroundTaskIfNeeded()
        }
    }
    
    private func cancelBackgroundTaskIfNeeded() {
        if let id = backgroundTaskID {
            trace(.warning, components: "Ending background task: \(id)")
            UIApplication.shared.endBackgroundTask(id)
            backgroundTaskID = nil
        }
    }
    
    // MARK: - Overlay -
    
    private func createOverlay() {
        guard let window = window else {
            return
        }
        
        let controller = UIHostingController(rootView: ScanScreen.Placeholder())
        controller.view.backgroundColor = .backgroundMain
        controller.view.bounds = window.bounds
        controller.view.frame = window.bounds
        coverController = controller
    }
    
    private func addOverlayIfNeeded() {
        if let coverController = coverController {
            window?.subviews.last?.addSubview(coverController.view)
        }
    }
    
    private func destroyOverlay() {
        coverController?.view.removeFromSuperview()
        coverController = nil
    }
    
    private func fadeOutOverlay(delay: TimeInterval) {
        UIView.animate(withDuration: 0.15, delay: delay, options: .curveLinear) {
            self.coverController?.view.alpha = 0.0
        } completion: { _ in
            self.destroyOverlay()
        }
    }

    // MARK: - URL Schemes -
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        guard let action = appContainer.deepLinkController.handle(open: url) else {
            return false
        }
        
        return handleAction(action: action)
    }
    
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        guard
            userActivity.activityType == NSUserActivityTypeBrowsingWeb,
            let url = userActivity.webpageURL
        else {
            return false
        }
        
        guard let action = appContainer.deepLinkController.handle(open: url) else {
            return false
        }
        
        // Calling assignHost() during app launch (when the app
        // hasn't been running) results in a double call making
        // it hang for ~10 seconds. Still uncertain of the exact
        // cause of the problem
        if hasBeenBackgrounded {
            
            // Reset the view in the event that the app handles
            // any deep links to ensure a consistent experience
            assignHost()
        }
        
        return handleAction(action: action)
    }
    
    private func handleAction(action: DeepLinkAction) -> Bool {
        if let confirmationDescription = action.confirmationDescription {
            appContainer.bannerController.show(
                style: .error,
                title: confirmationDescription.title,
                description: confirmationDescription.description,
                position: .bottom,
                actionStyle: .stacked,
                actions: [
                    .destructive(title: confirmationDescription.confirmation) { [unowned self] in
                        execute(action: action)
                    },
                    .cancel(title: Localized.Action.cancel),
                ]
            )
            
        } else {
            execute(action: action)
        }
        
        return true
    }
    
    private func execute(action: DeepLinkAction) {
        Task {
            try await action.executeAction()
        }
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
        
        let tableView = UITableView.appearance()
        tableView.backgroundColor = UIColor.backgroundMain
        tableView.separatorStyle = .singleLine
        tableView.separatorInset = UIEdgeInsets(top: 0.0, left: 20.0, bottom: 0.0, right: 0.0)
        tableView.separatorColor = .rowSeparator
        tableView.showsVerticalScrollIndicator = false
        tableView.showsHorizontalScrollIndicator = false
        
        let selectionView = UIView()
        selectionView.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        
        let textView = UITextView.appearance()
        textView.backgroundColor = .clear
        
        let scrollView = UIScrollView.appearance()
        scrollView.keyboardDismissMode = .onDrag
    }
}

extension Client: ObservableObject {}

extension UIApplication {
    static var shouldPauseInterfaceReset: Bool = false
}

extension UINavigationController {
    open override func viewWillLayoutSubviews() {
        // Remove the back button in all navigation stacks
        navigationBar.topItem?.backBarButtonItem = UIBarButtonItem(
            title: "",
            style: .plain,
            target: nil,
            action: nil
        )
    }
}
