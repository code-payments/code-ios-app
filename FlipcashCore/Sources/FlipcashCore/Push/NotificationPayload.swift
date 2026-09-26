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

    /// The message a CHAT push carries inline, or `nil` when the push isn't a chat message, carries
    /// no chat metadata, predates the server embedding the message, carries content this client
    /// can't represent, or only carries the message's id (a long message — see
    /// `Flipcash_Push_V1_ChatMetadata.messageRef`).
    ///
    /// The embedded message is the only part of a push that needs no network to become store rows.
    /// It carries the same `eventSequence` the transcript fetch would return for it, so it merges
    /// with a fetched message rather than competing with one.
    ///
    /// TODO(push/v1/model.proto ChatMetadata.message_ref): when only `messageID` is present, this
    /// returns nil rather than fetching the message via `Messaging.GetMessage`. The notification
    /// service extension's transcript prefetch (`NotificationService.cachePreview`) already fetches
    /// the chat's recent messages independently of this value, so the id-only case is not silently
    /// dropped in practice — it just doesn't get the "needs no network" fast path this doc comment
    /// describes. Wire up a `GetMessage` fetch here (or at the call site) if that gap matters.
    public static func chatMessage(_ userInfo: [AnyHashable: Any]) -> ConversationMessage? {
        guard let payload = decode(userInfo), payload.category == .chat, payload.hasChatMetadata else {
            return nil
        }
        switch payload.chatMetadata.messageRef {
        case .message(let message):
            return ConversationMessage(message)
        case .messageID, nil:
            return nil
        }
    }

    /// Whether the recipient had the chat muted when a CHAT push was sent. The push is still
    /// delivered so the client can store the message, but the client must not present a
    /// notification for it. `false` when the push isn't a chat message or carries no chat metadata
    /// (system messages, or a legacy server that omits it).
    ///
    /// Both presentation paths read this: the app's foreground delegate via
    /// ``presentationDecision(_:isViewingConversation:)``, and the notification service extension,
    /// which has no access to local state and so has nothing else to read.
    public static func isMuted(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let payload = decode(userInfo), payload.category == .chat, payload.hasChatMetadata else {
            return false
        }
        return payload.chatMetadata.muted
    }
}
