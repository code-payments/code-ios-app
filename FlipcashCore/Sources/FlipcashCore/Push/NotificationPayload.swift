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
    /// When only the message's id is present, ``chatMessageID(_:)`` names it for a `GetMessage` fetch.
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

    /// The id of the message a CHAT push is about, whether the push embeds it or only names it.
    /// Nil when the push isn't a chat message or carries no message reference.
    public static func chatMessageID(_ userInfo: [AnyHashable: Any]) -> MessageID? {
        guard let payload = decode(userInfo), payload.category == .chat, payload.hasChatMetadata else {
            return nil
        }
        switch payload.chatMetadata.messageRef {
        case .message(let message):
            return MessageID(message.messageID)
        case .messageID(let id):
            return MessageID(id)
        case nil:
            return nil
        }
    }

    /// The banner body for an end-to-end-encrypted push: the preview of message `messageID` when it
    /// arrived encrypted and decrypted to text or a photo, led by `senderName(senderID)` as
    /// "Name: …" when that returns a name. Nil keeps the server's body — the message is missing, was
    /// never encrypted, is neither text nor a photo, or didn't decrypt.
    public static func decryptedBody(
        of messageID: MessageID?,
        in messages: [ConversationMessage],
        senderName: (UserID) -> String? = { _ in nil }
    ) -> String? {
        guard let messageID, let message = messages.first(where: { $0.id == messageID }), message.isEncrypted else {
            return nil
        }
        let preview: String
        switch message.content {
        case .text(let text):
            preview = text
        case .media(_, let caption):
            preview = ChatMediaStrings.listPreview(caption: caption)
        case .cash, .deleted, .encrypted, .widget, .system:
            return nil
        }
        guard let name = message.senderID.flatMap(senderName), !name.isEmpty else { return preview }
        return "\(name): \(preview)"
    }

    /// The sender's display name as the server spelled it in a CHAT push: the `fallback` of the
    /// user-ID substitution naming `chatMetadata.sendingUserID`. Nil when the push names no sender
    /// that way.
    public static func senderName(_ userInfo: [AnyHashable: Any]) -> String? {
        guard let payload = decode(userInfo), payload.category == .chat, payload.hasChatMetadata,
              payload.chatMetadata.hasSendingUserID
        else {
            return nil
        }
        let senderID = payload.chatMetadata.sendingUserID.value
        let substitution = (payload.titleSubstitutions + payload.bodySubstitutions).first { substitution in
            guard case .userIDToDisplayName(let userID) = substitution.kind else { return false }
            return userID.value == senderID
        }
        guard let name = substitution?.fallback, !name.isEmpty else { return nil }
        return name
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
