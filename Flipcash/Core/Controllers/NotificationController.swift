//
//  NotificationController.swift
//  Code
//
//  Created by Dima Bart on 2021-11-05.
//

import UIKit

/// Tracks app lifecycle and push notification events as incrementing counters.
///
/// Views can observe these counters to trigger refreshes when the app becomes
/// active or receives a push notification.
///
/// Inject via `@Environment(NotificationController.self)`.
@Observable
class NotificationController {

    /// Incremented each time the app becomes active.
    private(set) var didBecomeActive:   Int = 0

    /// Incremented each time the app resigns active.
    private(set) var willResignActive:  Int = 0

    /// Incremented when a push notification is tapped.
    private(set) var pushReceived:      Int = 0

    /// Incremented when a push notification arrives while the app is open.
    private(set) var pushWillPresent:   Int = 0

    /// Incremented when a message notification is received.
    private(set) var messageReceived:   Int = 0

    @ObservationIgnored private var observers: [Any] = []

    // MARK: - Init -

    init() {
        observe(UIApplication.didBecomeActiveNotification)  { $0.didBecomeActive += 1 }
        observe(UIApplication.willResignActiveNotification) { $0.willResignActive += 1 }
        observe(.pushNotificationReceived)                  { $0.pushReceived += 1 }
        observe(.pushNotificationWillPresent)               { $0.pushWillPresent += 1 }
        observe(.messageNotificationReceived)               { $0.messageReceived += 1 }
    }

    isolated deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func observe(_ name: Notification.Name, handler: @escaping @MainActor (NotificationController) -> Void) {
        let token = NotificationCenter.default.addObserver(
            forName: name,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                handler(self)
            }
        }
        observers.append(token)
    }
}

extension NSNotification.Name {
    static let pushNotificationReceived    = Notification.Name("com.code.pushNotificationReceived")
    static let pushNotificationWillPresent = Notification.Name("com.code.pushNotificationWillPresent")
    static let pushDeepLinkReceived         = Notification.Name("com.code.pushDeepLinkReceived")
    static let qrDeepLinkReceived          = Notification.Name("com.code.qrDeepLinkReceived")
    static let messageNotificationReceived = Notification.Name("com.code.messageNotificationReceived")
}
