//
//  PushController.swift
//  Flipcash
//
//  Created by Dima Bart on 2022-08-12.
//

import UIKit
import FlipcashCore

@preconcurrency import Firebase
@preconcurrency import FirebaseInstallations
@preconcurrency import UserNotifications

private let logger = Logger(label: "flipcash.push-controller")

/// Manages push notification registration, Firebase Cloud Messaging tokens,
/// and APNs lifecycle.
///
/// On init, checks the current authorization status and registers for remote
/// notifications if previously authorized. Re-checks status each time the app
/// becomes active (e.g. after the user changes permissions in Settings).
///
/// Inject via `@Environment(PushController.self)`.
@MainActor @Observable
class PushController {

    /// The current notification authorization status, refreshed on app activation.
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    @ObservationIgnored private let owner: KeyPair
    @ObservationIgnored private let client: FlipClient
    @ObservationIgnored private let center: UNUserNotificationCenter
    @ObservationIgnored private let delegate: NotificationDelegate

    @ObservationIgnored private var apnsToken: Data?
    @ObservationIgnored private var uploadedFirebaseToken: String?
    @ObservationIgnored private var activeObserver: Any?

    // MARK: - Init -

    init(owner: KeyPair, client: FlipClient) {
        self.owner    = owner
        self.client   = client
        self.center   = .current()
        self.delegate = NotificationDelegate()

        delegate.didReceiveFCMToken = { [weak self] token in
            try await self?.didReceiveFirebaseToken(token: token)
        }

        center.delegate = delegate
        Messaging.messaging().delegate = delegate

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
    
    /// Deletes the FCM token from the server and unregisters from APNs.
    func prepareForLogout() {
        Task {
            guard let token = uploadedFirebaseToken else {
                return
            }
            
            try await deleteFirebaseToken(token)
        }
        
        unregisterAPNS()
    }
    
    // MARK: - Authorization Status -

    /// Re-fetches the notification authorization status from the system.
    func refreshAuthorizationStatus() async {
        authorizationStatus = await Self.fetchStatus()
    }
    
    // MARK: - Firebase -
    
    private func didReceiveFirebaseToken(token: String?) async throws {
        guard let token else {
            uploadedFirebaseToken = nil
            logger.warning("APNS: Firebase token cleared.")
            return
        }
        
        if uploadedFirebaseToken != token {
            try await client.addToken(
                token: token,
                installationID: try await Self.installationID(),
                owner: owner
            )
            uploadedFirebaseToken = token // Cache uploaded token
            
        }
    }
    
    private func deleteFirebaseToken(_ token: String) async throws {
        try await client.deleteTokens(
            installationID: try await Self.installationID(),
            owner: owner
        )
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
    
    static func fetchStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
    
    static func installationID() async throws -> String {
        try await Installations.installations().installationID()
    }
}

// MARK: - UNUserNotificationCenterDelegate -

@MainActor
private class NotificationDelegate: NSObject, @preconcurrency UNUserNotificationCenterDelegate, @preconcurrency MessagingDelegate {
    
    var didReceiveFCMToken: (@MainActor (String?) async throws -> Void)?
    
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
        
        Messaging.messaging().appDidReceiveMessage(notification.request.content.userInfo)

        // We intentionally don't call handleTargetUrlIfNeeded here.
        // Deep link navigation should only happen when user taps the notification,
        // which is handled in didReceive. This prevents unwanted navigation when
        // a notification arrives while the app is already open.

        Task { @MainActor in
            NotificationCenter.default.post(name: .pushNotificationWillPresent, object: nil)
        }
        
        return [.badge, .list, .sound, .banner]
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        logger.info("Received notification response", metadata: ["action": "\(response.actionIdentifier)"])
        
        Messaging.messaging().appDidReceiveMessage(response.notification.request.content.userInfo)
        
        let aps = response.notification.request.content.userInfo["aps"] as? [String: Any]
        handleTargetUrlIfNeeded(aps?["target_url"] as? String)
        
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

        logger.debug("Forwarding notification target_url to deep link handler", metadata: ["url": "\(url.sanitizedForAnalytics)"])

        Task { @MainActor in
            NotificationCenter.default.post(
                name: .pushDeepLinkReceived,
                object: nil,
                userInfo: ["url": url]
            )
        }
    }
}

extension PushController {
    static let mock: PushController = PushController(owner: .mock, client: .mock)
}
