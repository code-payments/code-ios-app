//
//  NotificationController.swift
//  Code
//
//  Created by Dima Bart on 2021-11-05.
//

import UIKit

@MainActor
class NotificationController: ObservableObject {
    
    @Published private(set) var didBecomeActive:   Int = 0
    @Published private(set) var willResignActive:  Int = 0
    @Published private(set) var didTakeScreenshot: Int = 0
    
    @Published private(set) var pushReceived:      Int = 0
    @Published private(set) var pushWillPresent:   Int = 0
    @Published private(set) var messageReceived:   Int = 0
    
    // MARK: - Init -
    
    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActiveNotification),       name: UIApplication.didBecomeActiveNotification,       object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willResignActiveNotification),      name: UIApplication.willResignActiveNotification,      object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(userDidTakeScreenshotNotification), name: UIApplication.userDidTakeScreenshotNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(pushReceivedNotification),          name: .pushNotificationReceived,                       object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(pushWillPresentNotification),       name: .pushNotificationWillPresent,                    object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(messageReceivedNotification),       name: .messageNotificationReceived,                    object: nil)
    }
    
    @objc private func didBecomeActiveNotification() {
        self.didBecomeActive += 1
    }
    
    @objc private func willResignActiveNotification() {
        self.willResignActive += 1
    }
    
    @objc private func userDidTakeScreenshotNotification() {
        self.didTakeScreenshot += 1
    }
    
    @objc private func pushReceivedNotification() {
        self.pushReceived += 1
    }
    
    @objc private func pushWillPresentNotification() {
        self.pushWillPresent += 1
    }
    
    @objc private func messageReceivedNotification() {
        self.messageReceived += 1
    }
}

extension NSNotification.Name {
    static let pushNotificationReceived    = Notification.Name("com.code.pushNotificationReceived")
    static let pushNotificationWillPresent = Notification.Name("com.code.pushNotificationWillPresent")
    static let messageNotificationReceived = Notification.Name("com.code.messageNotificationReceived")
    static let twitterNotificationReceived = Notification.Name("com.code.twitterNotificationReceived")
}
