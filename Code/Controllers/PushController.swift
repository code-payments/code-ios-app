//
//  PushController.swift
//  Code
//
//  Created by Dima Bart on 2022-08-12.
//

import UIKit
import UserNotifications
import Combine
import CodeServices
import Firebase

@MainActor
class PushController: ObservableObject {
    
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .denied
    
    private let sessionAuthenticator: SessionAuthenticator
    private let client: Client
    private let center: UNUserNotificationCenter
    private let delegate: NotificationDelegate
    private let firebase: Messaging
    
    private var apnsToken: Data?
    private var firebaseToken: String?
    
    private var stateSubscription: AnyCancellable?
    
    // MARK: - Init -
    
    init(sessionAuthenticator: SessionAuthenticator, client: Client) {
        self.sessionAuthenticator = sessionAuthenticator
        self.client   = client
        self.center   = .current()
        self.firebase = Messaging.messaging()
        self.delegate = NotificationDelegate(firebase: firebase)
        
        delegate.didReceiveFCMToken = { [weak self] token in
            self?.didReceiveFirebaseToken(token: token)
        }
        
        center.delegate = delegate
        firebase.delegate = delegate
        
        updateStatus()
        register()
        resetAppBadgeCount()
        
        stateSubscription = sessionAuthenticator.$state.sink { [weak self] state in
            // Subscriptions are invoked with `willSet` semantics so we need
            // to ensure that we execute the "isLoggedIn" check on the subsequent
            // runloop when that property has been updated.
            Task {
                if case .loggedIn = state, let firebaseToken = self?.firebaseToken {
                    trace(.note, components: "Firebase token cached.", "Token: \(firebaseToken)")
                    self?.didReceiveFirebaseToken(token: firebaseToken)
                }
            }
        }
    }
    
    private func register() {
        trace(.warning, components: "Registering for APNs token...")
        UIApplication.shared.registerForRemoteNotifications()
    }
    
    func didReceiveRemoteNotificationToken(with token: Data) {
        trace(.warning, components: "Received APNs token: \(token.hexEncodedString())")
        apnsToken = token
        firebase.setAPNSToken(token, type: .unknown)
    }
    
    // MARK: - Badge -
    
    func appDidBecomeActive() {
        resetAppBadgeCount()
    }
    
    func appWillResignActive() {
        resetAppBadgeCount()
    }
    
    private func resetAppBadgeCount() {
        UIApplication.shared.applicationIconBadgeNumber = 0
        if case .loggedIn(let container) = sessionAuthenticator.state {
            Task {
                try await client.resetBadgeCount(for: container.session.organizer.ownerKeyPair)
            }
        }
    }
    
    // MARK: - Firebase -
    
    private func didReceiveFirebaseToken(token: String?) {
        firebaseToken = token
        if let firebaseToken {
            if case .loggedIn(let container) = sessionAuthenticator.state {
                let containerID = container.session.user.containerID
                let owner = container.session.organizer.ownerKeyPair
                
                Task {
                    trace(.success, components: "Firebase token received. Sending to server...", "Token: \(firebaseToken)")
                    try await client.addToken(
                        firebaseToken: firebaseToken,
                        containerID: containerID,
                        owner: owner,
                        installationID: try await AppContainer.installationID()
                    )
                }
            } else {
                trace(.failure, components: "Firebase token received but no owner association stored. Can't send to server.")
            }
            
        } else {
            trace(.warning, components: "Firebase token cleared.")
        }
    }
    
    // MARK: - Authorization -
    
    func authorize(completion: @escaping (UNAuthorizationStatus) -> Void) {
        Task {
            do {
                try await center.requestAuthorization(options: [.alert, .badge, .sound])
            } catch {
                trace(.failure, components: "Failed to request authorization status: \(error)")
            }
            
            self.register()
            
            self.authorizationStatus = await center.notificationSettings().authorizationStatus
            completion(self.authorizationStatus)
        }
    }
    
    private func updateStatus() {
        Task {
            self.authorizationStatus = await center.notificationSettings().authorizationStatus
        }
    }
}

extension PushController {
    static func getAuthorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}

// MARK: - UNUserNotificationCenterDelegate -

@MainActor
private class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, MessagingDelegate {
    
    var didReceiveFCMToken: ((String?) -> Void)?
    
    let firebase: Messaging
    
    init(firebase: Messaging) {
        self.firebase = firebase
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
        
        firebase.appDidReceiveMessage(notification.request.content.userInfo)
        
        DispatchQueue.main.async {
            let category = notification.request.content.categoryIdentifier
            switch category {
            case "ChatMessage":
                NotificationCenter.default.post(name: .messageNotificationReceived, object: nil)
            case "Twitter":
                NotificationCenter.default.post(name: .twitterNotificationReceived, object: nil)
            default:
                NotificationCenter.default.post(name: .pushNotificationReceived, object: nil)
            }
            
            ErrorReporting.breadcrumb(
                name: "[Push] Push notification shown",
                metadata: [
                    "category": category,
                ],
                type: .process
            )
        }
        
//        let isActive = await UIApplication.shared.applicationState == .active
        
        // Don't show notifications while active
//        let options: UNNotificationPresentationOptions = isActive ? [] : [.badge, .banner, .list, .sound]
        let options: UNNotificationPresentationOptions = [.badge, .banner, .list, .sound]
        
        return options
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        trace(.warning, components: "Received response: \(response.actionIdentifier)")
        
        firebase.appDidReceiveMessage(response.notification.request.content.userInfo)
        
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .pushNotificationReceived, object: nil)
        }
    }
    
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        trace(.warning, components: "Received FCM token: \(fcmToken ?? "nil")")
        DispatchQueue.main.async { [weak self] in
            self?.didReceiveFCMToken?(fcmToken)
        }
    }
}

extension NSNotification.Name {
    static let pushNotificationReceived = Notification.Name("com.code.pushNotificationReceived")
    static let messageNotificationReceived = Notification.Name("com.code.messageNotificationReceived")
    static let twitterNotificationReceived = Notification.Name("com.code.twitterNotificationReceived")
}
