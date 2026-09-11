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

    /// The DM chat this payment posts into.
    public var chatID: ConversationID {
        switch self {
        case .contactDm(let chatID, _, _):
            return chatID
        case .tipDm(let chatID, _, _):
            return chatID
        }
    }

    /// Whether this payment reports as a tip. Mirrors the `action` serialized
    /// below, so a caller reporting analytics reads the same value the wire
    /// carries instead of re-deriving it.
    public var isTip: Bool {
        switch self {
        case .contactDm:
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
                    $0.tipDmPayment = .with {
                        $0.location = origin.proto
                        $0.action = action.proto
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

    /// Sent from a resolved tipcard (scan or deep link).
    case tipcard

    /// Sent from the Send Cash action inside an existing tip DM thread.
    case chat

    var proto: Flipcash_Intent_V1_ChatMetadata.TipDmPayment.Location {
        switch self {
        case .tipcard: return .tipcard
        case .chat:    return .chat
        }
    }
}

/// The verb a tip DM payment reports to the server, alongside `TipOrigin`.
///
/// The proto's `Action.default` means "infer from location," which only
/// exists so the server can stay compatible with clients built before this
/// field shipped. This client has no such clients to be compatible with, so
/// `.default` has no local representation here: every `TipDmPayment` this
/// client builds sets `action` explicitly. That matters because proto3 gives
/// `Location` a zero value too (`TIPCARD`), so an unset `action` alongside a
/// `TIPCARD` location would be indistinguishable on the wire from a client
/// that deliberately declared a tip — `DEFAULT` and `TIPCARD` are both 0.
public enum TipDmAction: Sendable, CaseIterable {

    /// A Send Cash payment inside an already-initialized tip DM.
    case send

    /// A payment from a tip card, or the payment that opens the tip DM.
    case tip

    var proto: Flipcash_Intent_V1_ChatMetadata.TipDmPayment.Action {
        switch self {
        case .send: return .send
        case .tip:  return .tip
        }
    }
}
