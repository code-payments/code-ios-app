//
//  E2eePolicy.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Decides whether this client encrypts a conversation's messages, and so whether its UI may claim
/// end-to-end encryption.
///
/// The only reader of ``Conversation/useE2Ee``: once E2EE launches the server flag is ignored, and
/// dropping it is a change to this file alone.
public enum E2eePolicy {

    /// The official @flipcash account's user id. Its chat stays plaintext because the backend sends
    /// onboarding messages there and reads the replies.
    // TODO: set @flipcash user id
    public static let flipcashAccountID: UserID? = nil

    /// Whether messages in `conversation` are sent encrypted: a DM with the flag on that is not the
    /// @flipcash chat. Groups never encrypt.
    public static func shouldEncrypt(_ conversation: Conversation) -> Bool {
        shouldEncrypt(conversation, flipcashAccountID: flipcashAccountID)
    }

    static func shouldEncrypt(_ conversation: Conversation, flipcashAccountID: UserID?) -> Bool {
        switch conversation.type {
        case .group:
            return false
        case .contactDm, .tipDm:
            break
        }
        guard conversation.useE2Ee else { return false }
        if let flipcashAccountID, conversation.members.contains(where: { $0.userID == flipcashAccountID }) {
            return false
        }
        return true
    }
}
