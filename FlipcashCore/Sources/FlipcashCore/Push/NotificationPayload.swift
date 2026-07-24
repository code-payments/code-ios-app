//
//  NotificationPayload.swift
//  FlipcashCore
//

import Foundation
import FlipcashAPI

/// Decodes `Flipcash_Push_V1_Payload` from a `UNNotificationContent.userInfo`.
public enum NotificationPayload {

    /// Key the server writes into APS custom data.
    public static let userInfoKey = "flipcash_payload"

    /// Returns the typed payload, or `nil` if the dictionary doesn't carry one
    /// or the bytes don't decode.
    public static func decode(_ userInfo: [AnyHashable: Any]) -> Flipcash_Push_V1_Payload? {
        // Lives under `aps` on the APNs path; top-level is a fallback.
        let base64 = (userInfo[userInfoKey] as? String)
            ?? ((userInfo["aps"] as? [AnyHashable: Any])?[userInfoKey] as? String)
        guard let base64, let data = Data(base64Encoded: base64) else {
            return nil
        }
        return try? Flipcash_Push_V1_Payload(serializedBytes: data)
    }

    /// Whether `userInfo` carries a CONTACT_JOIN push.
    public static func isContactJoin(_ userInfo: [AnyHashable: Any]) -> Bool {
        decode(userInfo)?.category == .contactJoin
    }

    /// The conversation a CHAT push targets, or `nil` when the push isn't a chat
    /// message or carries no chat navigation.
    public static func chatID(_ userInfo: [AnyHashable: Any]) -> ConversationID? {
        guard let payload = decode(userInfo), payload.category == .chat else { return nil }
        guard case .chatID(let chatID) = payload.navigation.type else { return nil }
        return ConversationID(chatID)
    }

    /// The kind of DM a CHAT push targets (contact vs. tip), or `nil` when the push isn't a chat
    /// message or carries no chat metadata (system messages, or a legacy server that omits it).
    public static func chatType(_ userInfo: [AnyHashable: Any]) -> ConversationType? {
        guard let payload = decode(userInfo), payload.category == .chat, payload.hasChatMetadata else {
            return nil
        }
        return ConversationType(payload.chatMetadata.type)
    }
}
