//
//  ChatPaymentMetadata.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import SwiftProtobuf

/// Chat context attached to a direct contact payment. The server uses it to
/// post the payment as a cash message in the contact's DM (creating the chat
/// if it doesn't exist yet). Both phones must be payment-linked to their
/// respective accounts or the server rejects the intent.
public struct ChatPaymentMetadata: Sendable {

    public let chatID: ConversationID
    public let sourcePhoneE164: String
    public let destinationPhoneE164: String

    public init(chatID: ConversationID, sourcePhoneE164: String, destinationPhoneE164: String) {
        self.chatID = chatID
        self.sourcePhoneE164 = sourcePhoneE164
        self.destinationPhoneE164 = destinationPhoneE164
    }

    /// Serialized `flipcash.intent.v1.AppMetadata` for SubmitIntent's
    /// `Metadata.app_metadata` value.
    public func serializedAppMetadata() throws -> Data {
        try Flipcash_Intent_V1_AppMetadata.with {
            $0.chat = .with {
                $0.chatID = chatID.proto
                $0.contactDmPayment = .with {
                    $0.source = .with { $0.value = sourcePhoneE164 }
                    $0.destination = .with { $0.value = destinationPhoneE164 }
                }
            }
        }.serializedData()
    }
}
