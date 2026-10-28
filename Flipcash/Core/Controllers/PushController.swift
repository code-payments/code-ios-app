//
//  PushController.swift
//  Flipcash
//
//  Created by Dima Bart on 2022-08-12.
//

import UIKit
import UniformTypeIdentifiers
import FlipcashCore

import Firebase
import FirebaseInstallations
import UserNotifications

private let logger = Logger(label: "flipcash.push-controller")

/// Manages push notification registration, Firebase Cloud Messaging tokens,
/// and APNs lifecycle.
///
/// On init, checks the current authorization status and registers for remote
/// notifications if previously authorized. Re-checks status each time the app
/// becomes active (e.g. after the user changes permissions in Settings).
///
/// Inject via `@Environment(PushController.self)`.
@Observable
class PushController {

    /// The current notification authorization status, refreshed on app activation.
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// Queried in the foreground to decide whether an incoming chat push targets
    /// the conversation the user is already viewing, in which case it's suppressed.
    var isViewingConversation: (@MainActor (ConversationID) -> Bool)? {
        get { delegate.isViewingConversation }
        set { delegate.isViewingConversation = newValue }
    }

    /// Queried in the foreground to recognise an archived chat's push, which the extension has
    /// already judged (passive means not addressed to the viewer).
    var isArchived: (@MainActor (ConversationID) -> Bool)? {
        get { delegate.isArchived }
        set { delegate.isArchived = newValue }
    }

    /// Opens the notification status page when the user taps the test notification.
    var openNotificationStatus: (@MainActor () -> Void)? {
        get { delegate.openNotificationStatus }
        set { delegate.openNotificationStatus = newValue }
    }

    /// The last `didFailToRegisterForRemoteNotifications` error this launch, for the report.
    @ObservationIgnored private(set) var lastAPNsError: String?

    @ObservationIgnored private let owner: KeyPair
    @ObservationIgnored private let client: FlipClient
    @ObservationIgnored private let center: UNUserNotificationCenter
    @ObservationIgnored private let delegate: NotificationDelegate

    @ObservationIgnored private var apnsToken: Data?
    @ObservationIgnored private var uploadedFirebaseToken: String?
    @ObservationIgnored private var activeObserver: Any?
    @ObservationIgnored private let registrationStore: NotificationRegistrationStore

    // MARK: - Init -

    init(owner: KeyPair, client: FlipClient) {
        self.owner    = owner
        self.client   = client
        self.center   = .current()
        self.delegate = NotificationDelegate()
        self.registrationStore = NotificationRegistrationStore(owner: owner.publicKey)

        delegate.didReceiveFCMToken = { [weak self] token in
            try await self?.didReceiveFirebaseToken(token: token)
        }

        center.delegate = delegate
        Messaging.messaging().delegate = delegate

        registerNotificationCategories()

        activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshAuthorizationStatus()
            }
        }

        Task {
            await refreshAuthorizationStatus()

            // There's no point trying to retrieve the firebase token
            // if we're not authorized to send push as the call will
            // not return anything
            if authorizationStatus != .notDetermined {
                registerAPNS()
            }
        }
    }

    isolated deinit {
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
        }
    }

    /// Called by the app delegate when APNs delivers a device token.
    /// Forwards the token to Firebase and triggers FCM token upload.
    func didReceiveRemoteNotificationToken(with token: Data) {
        logger.info("Received APNs token", metadata: ["token": "\(token.hexString())"])
        apnsToken = token
        Messaging.messaging().setAPNSToken(token, type: .unknown)
        
        Task {
            let token = try await Messaging.messaging().token()
            try await didReceiveFirebaseToken(token: token)
        }
    }

    /// Called by the app delegate when APNs registration fails. Kept for the status page's report.
    func didFailToRegisterForRemoteNotifications(with error: Error) {
        lastAPNsError = "\(error)"
    }
    
    /// Deletes the FCM token from the server and unregisters from APNs.
    func prepareForLogout() {
        registrationStore.clear()

        Task {
            guard uploadedFirebaseToken != nil else {
                return
            }

            try await deleteFirebaseToken()
        }
        
        unregisterAPNS()
    }

    // MARK: - Badge -

    /// Clears the app icon badge. Called when the app becomes active and when it
    /// enters the background, so a server-set badge count doesn't linger after the
    /// user has opened the app.
    func clearBadgeCount() {
        center.setBadgeCount(0)
    }

    /// Removes delivered notifications for a single conversation from Notification
    /// Center. Called when the user opens that conversation, so reading a thread
    /// clears its own pushes without disturbing other chats or non-chat alerts.
    func clearDeliveredNotifications(for conversationID: ConversationID) async {
        let identifiers = await center.deliveredNotifications()
            .filter { NotificationPayload.chatID($0.request.content.userInfo) == conversationID }
            .map { $0.request.identifier }

        guard !identifiers.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    // MARK: - Authorization Status -

    /// Re-fetches the notification authorization status from the system.
    func refreshAuthorizationStatus() async {
        authorizationStatus = await Self.fetchStatus().authorizationStatus
    }

    // MARK: - Notification Status -

    /// The last recorded `AddToken` outcome for this account, from any call site.
    var savedRegistration: NotificationStatus.RegistrationRecord? {
        registrationStore.record
    }

    /// The last six characters of the current FCM token, for the report.
    var tokenSuffix: String? {
        uploadedFirebaseToken.map { String($0.suffix(6)) }
    }

    /// Fetches the current FCM token and calls `AddToken` with it, whether or not this token was
    /// already uploaded, so the status page sees a fresh answer. Gives up after
    /// ``NotificationStatus/registrationTimeout``.
    func checkRegistration(deletingToken: Bool = false) async -> NotificationStatus.Registration {
        let messaging = Messaging.messaging()
        if deletingToken {
            do {
                try await messaging.deleteToken()
            } catch {
                ErrorReporting.captureError(error, reason: "Failed to delete local FCM token")
            }
        }

        let token: String
        do {
            token = try await Self.withTimeout { try await Messaging.messaging().token() }
        } catch {
            if messaging.apnsToken == nil {
                logger.warning("No APNs token for registration check", metadata: ["error": "\(error)"])
                return .noAPNsToken
            }
            let result: NotificationStatus.RegistrationResult = error is CancellationError ? .transport : .unknown
            ErrorReporting.captureError(error, reason: "Failed to fetch FCM token for registration check")
            registrationStore.record = .init(at: .now, result: result, source: .statusPage)
            return .finished(result)
        }

        return .finished(await upload(token: token, source: .statusPage))
    }

    /// Posts the local test notification ``NotificationStatus/testDelay`` seconds from now. It has no
    /// category, so it carries neither the chat Reply action nor the chat content extension.
    func scheduleTestNotification() async throws {
        let content = UNMutableNotificationContent()
        content.title = "Test notification"
        content.body = "If you can see this, notifications are working."
        content.sound = .default
        content.threadIdentifier = NotificationStatus.testThreadIdentifier
        content.userInfo = [NotificationStatus.testUserInfoKey: true]

        let request = UNNotificationRequest(
            identifier: NotificationStatus.testThreadIdentifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: NotificationStatus.testDelay, repeats: false)
        )
        try await center.add(request)
    }
    
    // MARK: - Firebase -
    
    private func didReceiveFirebaseToken(token: String?) async throws {
        guard let token else {
            uploadedFirebaseToken = nil
            logger.warning("APNS: Firebase token cleared.")
            return
        }
        
        if uploadedFirebaseToken != token {
            // A first upload this launch follows login or launch; any later one is a rotation.
            let source: NotificationStatus.RegistrationSource = uploadedFirebaseToken == nil ? .login : .refresh
            await upload(token: token, source: source)
        }
    }

    /// Calls `AddToken`, caches the token on success and records the outcome for this account.
    @discardableResult
    private func upload(token: String, source: NotificationStatus.RegistrationSource) async -> NotificationStatus.RegistrationResult {
        let result: NotificationStatus.RegistrationResult
        do {
            let client = client
            let owner = owner
            try await Self.withTimeout {
                try await client.addToken(
                    token: token,
                    installationID: try await Self.installationID(),
                    owner: owner
                )
            }
            uploadedFirebaseToken = token // Cache uploaded token
            result = .ok
        } catch let error as ErrorAddToken {
            result = .init(error)
            ErrorReporting.captureError(error, reason: "Failed to add push token", metadata: ["source": source.rawValue])
        } catch is CancellationError {
            result = .transport
        } catch {
            result = .unknown
            ErrorReporting.captureError(error, reason: "Failed to add push token", metadata: ["source": source.rawValue])
        }

        registrationStore.record = .init(at: .now, result: result, source: source)
        logger.info("Recorded push registration", metadata: ["source": "\(source.rawValue)", "result": "\(result.rawValue)"])
        return result
    }

    /// Runs `operation`, throwing `CancellationError` if it outlasts ``NotificationStatus/registrationTimeout``.
    private static func withTimeout<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: NotificationStatus.registrationTimeout)
                throw CancellationError()
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw CancellationError() }
            return first
        }
    }
    
    private func deleteFirebaseToken() async throws {
        try await client.deleteTokens(
            installationID: try await Self.installationID(),
            owner: owner
        )
    }
    
    // MARK: - Categories -

    private func registerNotificationCategories() {
        let reply = UNTextInputNotificationAction(
            identifier: ChatNotificationCategory.replyActionID,
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Message"
        )
        let sendCash = UNNotificationAction(
            identifier: ChatNotificationCategory.sendCashActionID,
            title: "Send Cash",
            options: [.foreground]
        )
        let dm = UNNotificationCategory(
            identifier: ChatNotificationCategory.id,
            actions: [reply, sendCash],
            intentIdentifiers: [],
            options: []
        )
        // A group has no single payee for Send Cash to resolve, so its pushes get their own
        // category carrying Reply alone rather than an action that can only dead-end.
        let group = UNNotificationCategory(
            identifier: ChatNotificationCategory.groupID,
            actions: [reply],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([dm, group])
    }

    // MARK: - Registration -

    private func registerAPNS() {
        UIApplication.shared.registerForRemoteNotifications()
    }
    
    private func unregisterAPNS() {
        UIApplication.shared.unregisterForRemoteNotifications()
    }
}

extension PushController {
    @discardableResult
    static func authorizeAndRegister() async throws -> Bool {
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        if granted {
            UIApplication.shared.registerForRemoteNotifications()
        }
        return granted
    }
    
    static func fetchStatus() async -> UNNotificationSettings {
        await UNUserNotificationCenter.current().notificationSettings()
    }
    
    static func installationID() async throws -> String {
        try await Installations.installations().installationID()
    }

    /// Developer-only: puts the current FCM token on the device pasteboard.
    ///
    /// Sending a test push to a physical device needs the token, and there is
    /// no way to read it off the device otherwise — the log redactor strips it
    /// (correctly), Firebase keeps it in the keychain, and the extension is
    /// only reachable through a real push. The pasteboard is the one channel
    /// `devicectl` can read back. Triggered by `--copy-push-token`, so it never
    /// runs for a user and never persists the token to disk.
    static func copyTokenToPasteboard() async {
        // Firebase refuses to mint an FCM token before APNs has handed one over,
        // and that round trip is not finished at launch. Retry rather than fail:
        // the alternative is racing the network on every attempt.
        for attempt in 1...20 {
            do {
                let token = try await Messaging.messaging().token()
                await MainActor.run {
                    UIPasteboard.general.setItems(
                        [[UTType.utf8PlainText.identifier: token]],
                        options: [.localOnly: true]
                    )
                }
                logger.info("Copied FCM token to pasteboard", metadata: ["attempt": "\(attempt)"])
                return
            } catch {
                try? await Task.sleep(for: .seconds(2))
            }
        }
        logger.error("Failed to copy FCM token: no APNs token after 40s")
    }
}

// MARK: - UNUserNotificationCenterDelegate -

private class NotificationDelegate: NSObject, @preconcurrency UNUserNotificationCenterDelegate, @preconcurrency MessagingDelegate {
    
    var didReceiveFCMToken: (@MainActor (String?) async throws -> Void)?
    var isViewingConversation: (@MainActor (ConversationID) -> Bool)?
    var isArchived: (@MainActor (ConversationID) -> Bool)?
    var openNotificationStatus: (@MainActor () -> Void)?

    override init() {
        super.init()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        logger.info("Notification will present", metadata: [
            "date":     "\(notification.date)",
            "category": "\(notification.request.content.categoryIdentifier)",
            "thread":   "\(notification.request.content.threadIdentifier)",
            "title":    "\(notification.request.content.title)",
            "body":     "\(notification.request.content.body)",
        ])
        
        let userInfo = notification.request.content.userInfo

        // The local test notification has no push payload; show it even in the foreground.
        if NotificationStatus.isTestNotification(userInfo) {
            return [.banner, .list, .sound]
        }

        Messaging.messaging().appDidReceiveMessage(userInfo)

        postContactJoinIfNeeded(userInfo)

        // We intentionally don't call handleTargetUrlIfNeeded here.
        // Deep link navigation should only happen when user taps the notification,
        // which is handled in didReceive. This prevents unwanted navigation when
        // a notification arrives while the app is already open.

        Task { @MainActor in
            NotificationCenter.default.post(name: .pushNotificationWillPresent, object: nil)
        }

        // Stay silent for a muted chat and for the conversation the user is already reading; other
        // chats and every non-chat push still present normally. Everything above this point has
        // already run — the push is stored and counted either way, only the banner is withheld.
        let decision = NotificationPayload.presentationDecision(
            userInfo,
            isViewingConversation: { conversationID in isViewingConversation?(conversationID) == true },
            isArchived: { conversationID in isArchived?(conversationID) == true },
            deliveredPassive: notification.request.content.interruptionLevel == .passive
        )
        switch decision {
        case .present:
            break
        case .suppressedMuted, .suppressedOpenConversation, .suppressedArchived:
            logger.info("Suppressing chat push", metadata: [
                "reason": "\(decision)",
                "conversationID": "\(NotificationPayload.chatID(userInfo).map { "\($0)" } ?? "none")",
            ])
        }
        return decision.options
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        logger.info("Received notification response", metadata: ["action": "\(response.actionIdentifier)"])

        if NotificationStatus.isTestNotification(response.notification.request.content.userInfo) {
            openNotificationStatus?()
            return
        }

        Messaging.messaging().appDidReceiveMessage(response.notification.request.content.userInfo)

        postContactJoinIfNeeded(response.notification.request.content.userInfo)

        let userInfo = response.notification.request.content.userInfo
        let conversationID = NotificationPayload.chatID(userInfo)

        if let conversationID {
            // The push carries the chat it is about, so the tap routes on that
            // rather than on `target_url`: the same id an invite link carries,
            // through the same route, so a group the user hasn't joined lands on
            // the gated screen either way. `target_url` stays the fallback for
            // every non-chat push.
            handleDeepLink(URL.chatDeepLink(
                for: conversationID,
                sendCash: response.actionIdentifier == ChatNotificationCategory.sendCashActionID
            ))
        } else {
            let aps = userInfo["aps"] as? [String: Any]
            handleTargetUrlIfNeeded(aps?["target_url"] as? String)
        }

        Task { @MainActor in
            NotificationCenter.default.post(name: .pushNotificationReceived, object: nil)
        }
    }
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        logger.info("Received FCM token", metadata: ["token": "\(fcmToken ?? "nil")"])
        Task {
            try await self.didReceiveFCMToken?(fcmToken)
        }
    }
    
    private func handleTargetUrlIfNeeded(_ urlString: String?) {
        guard let urlString, let url = URL(string: urlString) else {
            logger.debug("No target_url in notification payload")
            return
        }

        handleDeepLink(url)
    }

    private func handleDeepLink(_ url: URL) {
        logger.debug("Forwarding notification deep link to handler", metadata: ["url": "\(url.sanitizedForAnalytics)"])

        Task { @MainActor in
            NotificationCenter.default.post(
                name: .pushDeepLinkReceived,
                object: nil,
                userInfo: ["url": url]
            )
        }
    }

    /// Posts `.contactDidJoinReceived` for a CONTACT_JOIN push so the contact-sync
    /// controller re-pulls the matched set and the recipient list reclassifies the
    /// joiner without waiting for a local address-book change.
    private func postContactJoinIfNeeded(_ userInfo: [AnyHashable: Any]) {
        guard NotificationPayload.isContactJoin(userInfo) else { return }
        Task { @MainActor in
            NotificationCenter.default.post(name: .contactDidJoinReceived, object: nil)
        }
    }
}

extension PushController {
    static let mock: PushController = PushController(owner: .mock, client: .mock)
}
