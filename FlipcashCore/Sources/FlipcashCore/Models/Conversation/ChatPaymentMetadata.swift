//
//  ChatPaymentMetadata.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import SwiftProtobuf

/// Chat context attached to a direct DM payment. The server uses it to post
/// the payment as a cash message in the DM (creating the chat if it doesn't
/// exist yet). Contact DMs require both phones to be payment-linked; tip DMs
/// are keyed on user IDs alone.
public enum ChatPaymentMetadata: Sendable {

    case contactDm(chatID: ConversationID, sourcePhoneE164: String, destinationPhoneE164: String)
    case tipDm(chatID: ConversationID, origin: TipOrigin, action: TipDmAction)
    /// A Send Cash payment to a member of a group chat. The destination owner account names the
    /// recipient; the server denies a tip, so the action is always `SEND`.
    case groupPayment(chatID: ConversationID)
    /// A payment that boosts the payer's own reaction with `emoji` on a message in a group chat.
    /// The payer must already have reacted; the server splits the payment between the message's
    /// sender and the group's creator and posts no message into the chat.
    case reactionBoost(chatID: ConversationID, messageID: MessageID, emoji: String)

    /// The chat this payment posts into.
    public var chatID: ConversationID {
        switch self {
        case .contactDm(let chatID, _, _):
            return chatID
        case .tipDm(let chatID, _, _):
            return chatID
        case .groupPayment(let chatID):
            return chatID
        case .reactionBoost(let chatID, _, _):
            return chatID
        }
    }

    /// Whether this payment reports as a tip. Mirrors the `action` serialized
    /// below, so a caller reporting analytics reads the same value the wire
    /// carries instead of re-deriving it.
    public var isTip: Bool {
        switch self {
        case .contactDm, .groupPayment, .reactionBoost:
            return false
        case .tipDm(_, _, let action):
            return action == .tip
        }
    }

    /// Serialized `flipcash.intent.v1.AppMetadata` for SubmitIntent's
    /// `Metadata.app_metadata` value.
    public func serializedAppMetadata() throws -> Data {
        try Flipcash_Intent_V1_AppMetadata.with {
            $0.chat = .with {
                $0.chatID = chatID.proto
                switch self {
                case .contactDm(_, let sourcePhoneE164, let destinationPhoneE164):
                    $0.contactDmPayment = .with {
                        $0.source = .with { $0.value = sourcePhoneE164 }
                        $0.destination = .with { $0.value = destinationPhoneE164 }
                    }
                case .tipDm(_, let origin, let action):
                    $0.dmPayment = .with {
                        $0.location = origin.proto
                        $0.action = action.proto
                    }
                case .groupPayment:
                    $0.groupPayment = .with { $0.action = .send }
                case .reactionBoost(_, let messageID, let emoji):
                    $0.reactionBoost = .with {
                        $0.messageID = messageID.proto
                        $0.emoji = .with { $0.value = emoji }
                    }
                }
            }
        }.serializedData()
    }
}

/// Where in the app a tip DM payment was sent from. Reported to the server so
/// it can attribute the tip to the surface it originated on. Mirrors Android's
/// `TipOrigin`.
public enum TipOrigin: Sendable {

    /// Sent from a scanned Flipcard, by camera or its profile QR link.
    case tipcard

    /// Sent from a chat or a profile, anywhere but a scanned Flipcard.
    case chat

    var proto: Flipcash_Intent_V1_ChatMetadata.DmPayment.Location {
        switch self {
        case .tipcard: return .flipcard
        case .chat:    return .chat
        }
    }
}

/// The verb a tip DM payment reports to the server, alongside `TipOrigin`.
///
/// The proto's `Action.default` means "infer from location," which only
/// exists so the server can stay compatible with clients built before this
/// field shipped. This client has no such clients to be compatible with, so
/// `.default` has no local representation here: every `DmPayment` this
/// client builds sets `action` explicitly. That matters because proto3 gives
/// `Location` a zero value too (`FLIPCARD`), so an unset `action` alongside a
/// `FLIPCARD` location would be indistinguishable on the wire from a client
/// that deliberately declared a tip — `DEFAULT` and `FLIPCARD` are both 0.
public enum TipDmAction: Sendable, CaseIterable {

    /// A Send Cash payment to the DM's counterpart, including the one that
    /// opens the DM when it wasn't sent from a scanned Flipcard.
    case send

    /// A payment sent from a scanned Flipcard.
    case tip

    var proto: Flipcash_Intent_V1_PaymentAction {
        switch self {
        case .send: return .send
        case .tip:  return .tip
        }
    }
}
