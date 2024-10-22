//
//  NotificationModifier.swift
//  Code
//
//  Created by Dima Bart on 2024-02-09.
//

import UserNotifications
import CodeServices
import CodeAPI

class NotificationModifier {
    
    var handler: ((UNNotificationContent) -> Void)?
    var originalContent: UNMutableNotificationContent?
    
    init() {}
    
    func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        handler = contentHandler
        originalContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
        
        if let modifiedContent = originalContent {
            
            // Modify content
            if let (title, content) = extractChatContent(from: modifiedContent.userInfo) {
                modifiedContent.title = title.localizedStringByKey
                modifiedContent.body  = content.localizedText
            } else {
                // TODO: We may want a better fallback
                modifiedContent.body  = "You have a new message."
            }
            
            modifiedContent.interruptionLevel = .active
            
            contentHandler(modifiedContent)
        }
    }
    
    func serviceExtensionTimeWillExpire() {
        guard let originalContent else {
            return
        }
        
        handler?(originalContent)
    }
    
    // MARK: - Decoding -
    
    private func extractChatContent(from userInfo: [AnyHashable : Any]) -> (String, ChatLegacy.Content)? {
        guard
            let chatTitle = userInfo["chat_title"] as? String,
            let messageContent = userInfo["message_content"] as? String
        else {
            return nil
        }
        
        guard let messageData = messageContent.base64EncodedData() else {
            return nil
        }
        
        guard
            let rawContent = try? Code_Chat_V2_Content(serializedData: messageData),
            let content = ChatLegacy.Content(rawContent)
        else {
            return nil
        }
        
        return (chatTitle, content)
    }
}
