//
//  NotificationService.swift
//  CodePushExtension
//
//  Created by Dima Bart on 2024-02-08.
//

import UserNotifications

class NotificationService: UNNotificationServiceExtension {

    private let modifier = NotificationModifier()

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        modifier.didReceive(request, withContentHandler: contentHandler)
    }
    
    override func serviceExtensionTimeWillExpire() {
        modifier.serviceExtensionTimeWillExpire()
    }
}
