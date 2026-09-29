//
//  E2eePolicy.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import SharedCore

/// Decides whether this client encrypts a conversation's messages, and so whether its UI may claim
/// end-to-end encryption.
///
/// The only reader of ``Conversation/useE2Ee``. The rule itself, including the @flipcash exemption,
/// is shared-core's `ChatEncryptionPolicy`, so both apps agree on which chats encrypt.
public enum E2eePolicy {

    /// Whether messages in `conversation` are sent encrypted: a DM with the flag on that is not the
    /// @flipcash chat. Groups never encrypt.
    public static func shouldEncrypt(_ conversation: Conversation) -> Bool {
        let isDirectMessage: Bool
        switch conversation.type {
        case .group:
            isDirectMessage = false
        case .contactDm, .tipDm:
            isDirectMessage = true
        }
        // Self is never @flipcash, so requiring every member to pass as the peer exempts the
        // @flipcash chat without knowing which member is self. A member without an id has no key
        // to encrypt to.
        return !conversation.members.isEmpty && conversation.members.allSatisfy { member in
            guard let userID = member.userID else { return false }
            return ChatEncryptionPolicy.shared.shouldEncrypt(
                isDirectMessage: isDirectMessage,
                useE2ee: conversation.useE2Ee,
                peerUserId: SharedBytes.shared.byteArray(data: userID.data)
            )
        }
    }
}
