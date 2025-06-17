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
    
    private let owner: KeyPair
    private let client: FlipClient
    private let center: UNUserNotificationCenter
    private let delegate: NotificationDelegate
    
    private var apnsToken: Data?
    private var firebaseToken: String?
    
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
        
        Task {

            // There's no point trying to retrieve the firebase token
            // if we're not authorized to send push as the call will
            // not return anything
            guard await Self.fetchStatus() != .notDetermined else {
                return
            }
            
            do {
                let token = try await Messaging.messaging().token()
                trace(.note, components: "Uploading existing Firebase token from .messaging().token()")
                try await addFirebaseToken(token)
            } catch {
                trace(.failure, components: "No stored Firebase token. Is this a fresh launch?")
            }
        }
//        resetAppBadgeCount()
    }
    
    func didReceiveRemoteNotificationToken(with token: Data) {
        trace(.warning, components: "Received APNs token: \(token.hexString())")
        apnsToken = token
        Messaging.messaging().setAPNSToken(token, type: .unknown)
    }
    
    func prepareForLogout() {
        Task {
            guard let token = firebaseToken else {
                return
            }
            
            try await deleteFirebaseToken(token)
        }
    }
    
    // MARK: - Badge -
    
    func appDidBecomeActive() {
//        resetAppBadgeCount()
    }
    
    func appWillResignActive() {
//        resetAppBadgeCount()
    }
    
//    private func resetAppBadgeCount() {
//        UIApplication.shared.applicationIconBadgeNumber = 0
//        if case .loggedIn(let container) = sessionAuthenticator.state {
//            Task {
//                try await client.resetBadgeCount(for: container.session.organizer.ownerKeyPair)
//            }
//        }
//    }
    
    // MARK: - Firebase -
    
    private func didReceiveFirebaseToken(token: String?) async throws {
        firebaseToken = token
        if let firebaseToken {
            trace(.success, components: "APNS: Firebase token received. Sending to server...", "Token: \(firebaseToken)")
            try await client.addToken(
                token: firebaseToken,
                installationID: try await Self.installationID(),
                owner: owner
            )
            
        } else {
            trace(.warning, components: "APNS: Firebase token cleared.")
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
    
    func authorizeAndRegister() async throws {
        if await Self.fetchStatus() == .notDetermined {
            try await center.requestAuthorization(options: [.alert, .badge, .sound])
        }
        
        await register()
    }
    
    private func register() async {
        UIApplication.shared.registerForRemoteNotifications()
    }
}

extension PushController {
    static func authorize() async throws {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
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
        
        return [.badge, .list, .sound, .banner]
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        trace(.warning, components: "Received response: \(response.actionIdentifier)")
        
        Messaging.messaging().appDidReceiveMessage(response.notification.request.content.userInfo)
        
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
}

extension NSNotification.Name {
    static let pushNotificationReceived = Notification.Name("com.flipcash.pushController.notificationReceived")
}

extension PushController {
    static let mock: PushController = PushController(owner: .mock, client: .mock)
}
