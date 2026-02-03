//
//  PushController.swift
//  Flipchat
//
//  Created by Dima Bart on 2022-08-12.
//

import UIKit
import Combine
import FlipcashCore

@preconcurrency import Firebase
@preconcurrency import FirebaseInstallations
@preconcurrency import UserNotifications

@MainActor
class PushController: ObservableObject {

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let owner: KeyPair
    private let client: FlipClient
    private let center: UNUserNotificationCenter
    private let delegate: NotificationDelegate

    private var apnsToken: Data?
    private var uploadedFirebaseToken: String?
    
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didBecomeActiveNotification),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        Task {
            await refreshAuthorizationStatus()

            // There's no point trying to retrieve the firebase token
            // if we're not authorized to send push as the call will
            // not return anything
            if authorizationStatus == .notDetermined {
//                try await authorizeAndRegister()
                // Do nothing

            } else {
                // Triggering APNS registration invokes the
                // didReceiveRemoteNotificationToken function
                // which will uploaded the new push token
                registerAPNS()
            }
        }
//        resetAppBadgeCount()
    }

    @objc private func didBecomeActiveNotification() {
        Task {
            await refreshAuthorizationStatus()
        }
    }
    
    func didReceiveRemoteNotificationToken(with token: Data) {
        trace(.warning, components: "Received APNs token: \(token.hexString())")
        apnsToken = token
        Messaging.messaging().setAPNSToken(token, type: .unknown)
        
        Task {
            let token = try await Messaging.messaging().token()
            try await didReceiveFirebaseToken(token: token)
        }
    }
    
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

    func refreshAuthorizationStatus() async {
        authorizationStatus = await Self.fetchStatus()
    }
    
    // MARK: - Firebase -
    
    private func didReceiveFirebaseToken(token: String?) async throws {
        guard let token else {
            uploadedFirebaseToken = nil
            trace(.warning, components: "APNS: Firebase token cleared.")
            return
        }
        
        if uploadedFirebaseToken != token {
            trace(.success, components: "APNS: New Firebase token received. Sending to server...", "Token: \(token)")
            try await client.addToken(
                token: token,
                installationID: try await Self.installationID(),
                owner: owner
            )
            uploadedFirebaseToken = token // Cache uploaded token
            
        } else {
            trace(.note, components: "APNS: Received a token but it's identical to uploaded token.")
        }
    }
    
    private func addFirebaseToken(_ token: String) async throws {
        try await client.addToken(
            token: token,
            installationID: try await Self.installationID(),
            owner: owner
        )
    }
    
    private func deleteFirebaseToken(_ token: String) async throws {
        try await client.deleteTokens(
            installationID: try await Self.installationID(),
            owner: owner
        )
    }
    
    // MARK: - Authorization -
    
    private func authorizeAndRegister() async throws {
        if await Self.fetchStatus() == .notDetermined {
            try await center.requestAuthorization(options: [.alert, .badge, .sound])
        }
        
        registerAPNS()
    }
    
    private func registerAPNS() {
        UIApplication.shared.registerForRemoteNotifications()
    }
    
    private func unregisterAPNS() {
        UIApplication.shared.unregisterForRemoteNotifications()
    }
}

extension PushController {
    static func authorizeAndRegister() async throws {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        UIApplication.shared.registerForRemoteNotifications()
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
        trace(.warning, components: 
              "Date:     \(notification.date)",
              "Category: \(notification.request.content.categoryIdentifier)",
              "Thread:   \(notification.request.content.threadIdentifier)",
              "Title:    \(notification.request.content.title)",
              "Body:     \(notification.request.content.body)",
              "Info:     \(notification.request.content.userInfo)"
        )
        
        Messaging.messaging().appDidReceiveMessage(notification.request.content.userInfo)
        
        handleTargetUrlIfNeeded(notification.request.content.userInfo["target_url"] as? String)
                
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .pushNotificationWillPresent, object: nil)
        }
        
        return [.badge, .list, .sound, .banner]
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        trace(.warning, components: "Received response: \(response.actionIdentifier)")
        
        Messaging.messaging().appDidReceiveMessage(response.notification.request.content.userInfo)
        
        handleTargetUrlIfNeeded(response.notification.request.content.userInfo["target_url"] as? String)
        
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .pushNotificationReceived, object: nil)
        }
    }
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        trace(.warning, components: "Received FCM token: \(fcmToken ?? "nil")")
        Task {
            try await self.didReceiveFCMToken?(fcmToken)
        }
    }
    
    private func handleTargetUrlIfNeeded(_ urlString: String?) {
        guard let urlString, let url = URL(string: urlString) else {
            return
        }
        
        DispatchQueue.main.async {
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
