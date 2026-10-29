//
//  InviteLinkSecret.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import SharedCoreKit

/// The 32-byte secret in an invite link's `#s=` fragment.
///
/// The secret is the link's key material: whoever holds it can read the group's roster and join.
/// It is never printed: ``description`` and ``debugDescription`` are redacted, so a log line or a
/// navigation trace that interpolates one carries nothing.
public struct InviteLinkSecret: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {

    public let data: Data

    public init(data: Data) {
        self.data = data
    }

    /// The secret in a URL fragment (without its `#`), or nil when it holds none. Shared core owns
    /// the fragment grammar, so iOS and Android accept the same links.
    public init?(fragment: String) {
        guard let data = SharedInviteCipher.secret(fragment: fragment) else { return nil }
        self.data = data
    }

    public var description: String { "InviteLinkSecret(redacted)" }
    public var debugDescription: String { description }
}

// MARK: - Joining -

extension InviteLinkSecret {

    /// The bearer token the link presents to `GetInvite`, `GetRoster` and `JoinChat`.
    public func token() throws -> InviteToken {
        InviteToken(data: try SharedInviteCipher.inviteToken(secret: data))
    }

    /// What `JoinChat` takes to join through this link: the token, and the secret sealed to the
    /// joiner so that the invite's key bundle opens for them afterwards.
    public func joinParameters(owner: KeyPair, conversationID: ConversationID) throws -> InviteJoinParameters {
        let inviteID = try SharedInviteCipher.inviteId(secret: data)
        let envelope = try SharedInviteCipher.sealSecretEnvelope(
            owner: SharedEd25519.KeyPair(publicKey: Data(owner.publicKey.bytes), privateKey: Data(owner.privateKey.bytes)),
            secret: data,
            chatId: conversationID.data,
            inviteId: inviteID
        )
        return InviteJoinParameters(
            token: try token(),
            secretEnvelope: InviteSecretEnvelope(
                scheme: SharedCoreInviteSealer.scheme,
                nonce: envelope.nonce,
                ciphertext: envelope.ciphertext
            )
        )
    }
}
