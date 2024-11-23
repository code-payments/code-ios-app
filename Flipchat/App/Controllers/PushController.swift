//
//  PushController.swift
//  Flipchat
//
//  Created by Dima Bart on 2022-08-12.
//

import UIKit
import Combine
import FlipchatServices

@preconcurrency import Firebase
@preconcurrency import FirebaseInstallations
@preconcurrency import UserNotifications

@MainActor
class PushController: ObservableObject {
    
    static var activeChat: ChatID? = nil
    
    private let owner: KeyPair
    private let client: FlipchatClient
    private let center: UNUserNotificationCenter
    private let delegate: NotificationDelegate
    
    private var apnsToken: Data?
    private var firebaseToken: String?
    
    // MARK: - Init -
    
    init(owner: KeyPair, client: FlipchatClient) {
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
        try await client.deleteToken(
            token: token,
            owner: owner
        )
    }
    
    // MARK: - Authorization -
    
    func authorizeAndRegister() async throws {
        if await Self.fetchStatus() == .notDetermined {
            try await authorize()
        }
        
        await register()
    }
    
    func register() async {
        UIApplication.shared.registerForRemoteNotifications()
    }
    
    private func authorize() async throws {
        try await center.requestAuthorization(options: [.alert, .badge, .sound])
        await register()
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
private class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, MessagingDelegate {
    
    var didReceiveFCMToken: (@MainActor (String?) async throws -> Void)?
    
    nonisolated
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
        
        var showBanners = true
        if
            let base64ChatID = notification.request.content.userInfo["chat_id"] as? String,
            let chatID = Data(base64Encoded: base64ChatID)
        {
            print("Skipping banners, chat is currently active")
            showBanners = await PushController.activeChat?.data != chatID
        }
        
        var options: UNNotificationPresentationOptions = [.badge, .list, .sound]
        if showBanners {
            options.insert(.banner)
        }
        
        return options
    }
    
    nonisolated
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        trace(.warning, components: "Received response: \(response.actionIdentifier)")
        
        Messaging.messaging().appDidReceiveMessage(response.notification.request.content.userInfo)
        
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .pushNotificationReceived, object: nil)
        }
    }
    
    nonisolated
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        trace(.warning, components: "Received FCM token: \(fcmToken ?? "nil")")
        Task {
            try await self.didReceiveFCMToken?(fcmToken)
        }
    }
}
