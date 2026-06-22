//
//  NotificationViewController.swift
//  NotificationContent
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import UIKit
import UserNotifications
import UserNotificationsUI

/// Rich content for a chat-message notification: a portion of the real chat
/// (the last few messages, rendered with the app's own bubbles), fed by a
/// server fetch. Wired up in the next task; this is the target's entry point.
final class NotificationViewController: UIViewController, UNNotificationContentExtension {

    func didReceive(_ notification: UNNotification) {
        // Implemented in the content-rendering task.
    }
}
