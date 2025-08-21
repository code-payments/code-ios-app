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
        
        Task {

            // There's no point trying to retrieve the firebase token
            // if we're not authorized to send push as the call will
            // not return anything
            if await Self.fetchStatus() == .notDetermined {
                try await authorizeAndRegister()
                
            } else {
                // Triggering APNS registration invokes the
                // didReceiveRemoteNotificationToken function
                // which will uploaded the new push token
                registerAPNS()
            }
        }
//        resetAppBadgeCount()
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

extension PushController {
    static let mock: PushController = PushController(owner: .mock, client: .mock)
}
