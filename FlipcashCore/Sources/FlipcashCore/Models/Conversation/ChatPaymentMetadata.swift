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
    case tipDm(chatID: ConversationID)

    /// The DM chat this payment posts into.
    public var chatID: ConversationID {
        switch self {
        case .contactDm(let chatID, _, _):
            return chatID
        case .tipDm(let chatID):
            return chatID
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
                case .tipDm:
                    $0.tipDmPayment = .init()
                }
            }
        }.serializedData()
    }
}
