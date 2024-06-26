//
//  NotificationController.swift
//  Code
//
//  Created by Dima Bart on 2021-11-05.
//

import UIKit

class NotificationController: ObservableObject {
    
    @Published private(set) var didBecomeActive:   Int = 0
    @Published private(set) var willResignActive:  Int = 0
    @Published private(set) var didTakeScreenshot: Int = 0
    
    @Published private(set) var pushReceived:      Int = 0
    @Published private(set) var messageReceived:   Int = 0
    
    // MARK: - Init -
    
    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActiveNotification),       name: UIApplication.didBecomeActiveNotification,       object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willResignActiveNotification),      name: UIApplication.willResignActiveNotification,      object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(userDidTakeScreenshotNotification), name: UIApplication.userDidTakeScreenshotNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(pushReceivedNotification),          name: .pushNotificationReceived,                       object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(messageReceivedNotification),       name: .messageNotificationReceived,                    object: nil)
    }
    
    @objc private func didBecomeActiveNotification() {
        DispatchQueue.main.async {
            self.didBecomeActive += 1
        }
    }
    
    @objc private func willResignActiveNotification() {
        DispatchQueue.main.async {
            self.willResignActive += 1
        }
    }
    
    @objc private func userDidTakeScreenshotNotification() {
        DispatchQueue.main.async {
            self.didTakeScreenshot += 1
        }
    }
    
    @objc private func pushReceivedNotification() {
        DispatchQueue.main.async {
            self.pushReceived += 1
        }
    }
    
    @objc private func messageReceivedNotification() {
        DispatchQueue.main.async {
            self.messageReceived += 1
        }
    }
}
