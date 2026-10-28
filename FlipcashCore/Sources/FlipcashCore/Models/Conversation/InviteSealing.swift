//
//  InviteSealing.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// What `createInvite` needs from a fresh link secret: the token and the two envelopes.
public struct InviteMint: Sendable {
    public let token: InviteToken
    public let keyEnvelope: InviteKeyEnvelope
    public let secretEnvelope: InviteSecretEnvelope

    public init(token: InviteToken, keyEnvelope: InviteKeyEnvelope, secretEnvelope: InviteSecretEnvelope) {
        self.token = token
        self.keyEnvelope = keyEnvelope
        self.secretEnvelope = secretEnvelope
    }
}

/// The inviter's side of the invite crypto, behind a protocol so the screens that make and list
/// links run against a fake in tests.
public protocol InviteSealing: Sendable {
    /// A fresh 32-byte link secret.
    func newSecret() -> Data

    /// Derives the token and seals the chat key and the secret for one invite.
    func mint(secret: Data, owner: KeyPair, conversationID: ConversationID, groupKey: Data) throws -> InviteMint

    /// The link that carries `secret` in its fragment.
    func link(secret: Data) throws -> URL

    /// The secret behind an invite `owner` created, or `nil` when its envelope doesn't open here.
    func secret(of invite: Invite, owner: KeyPair) -> Data?
}

/// ``InviteSealing`` over SharedCoreKit's ``SharedInviteCipher``.
public struct SharedCoreInviteSealer: InviteSealing {

    /// The `InviteKeyEnvelope.Scheme` and `InviteSecretEnvelope.Scheme` this client seals and opens.
    static let scheme = 1

    public init() {}

    public func newSecret() -> Data {
        SharedInviteCipher.newSecret()
    }

    public func mint(secret: Data, owner: KeyPair, conversationID: ConversationID, groupKey: Data) throws -> InviteMint {
        let inviter = owner.sharedKeyPair
        let token = try SharedInviteCipher.inviteToken(secret: secret)
        let inviteID = try SharedInviteCipher.inviteId(secret: secret)
        let keyEnvelope = try SharedInviteCipher.sealKeyEnvelope(
            inviter: inviter,
            secret: secret,
            chatId: conversationID.data,
            chatKey: groupKey
        )
        let secretEnvelope = try SharedInviteCipher.sealSecretEnvelope(
            owner: inviter,
            secret: secret,
            chatId: conversationID.data,
            inviteId: inviteID
        )
        return InviteMint(
            token: InviteToken(data: token),
            keyEnvelope: InviteKeyEnvelope(
                scheme: Self.scheme,
                nonce: keyEnvelope.nonce,
                ciphertext: keyEnvelope.ciphertext,
                signature: keyEnvelope.signature
            ),
            secretEnvelope: InviteSecretEnvelope(
                scheme: Self.scheme,
                nonce: secretEnvelope.nonce,
                ciphertext: secretEnvelope.ciphertext
            )
        )
    }

    public func link(secret: Data) throws -> URL {
        let string = try SharedInviteCipher.link(secret: secret)
        guard let url = URL(string: string) else { throw InviteLinkMalformed() }
        return url
    }

    public func secret(of invite: Invite, owner: KeyPair) -> Data? {
        guard let envelope = invite.secretEnvelope, envelope.scheme == Self.scheme else { return nil }
        return try? SharedInviteCipher.openSecretEnvelope(
            owner: owner.sharedKeyPair,
            chatId: invite.conversationID.data,
            inviteId: invite.id.data,
            envelope: SharedInviteCipher.SecretEnvelope(nonce: envelope.nonce, ciphertext: envelope.ciphertext)
        )
    }
}

/// Shared core built a link Foundation can't parse.
public struct InviteLinkMalformed: Error {}

private extension KeyPair {
    var sharedKeyPair: SharedEd25519.KeyPair {
        SharedEd25519.KeyPair(publicKey: Data(publicKey.bytes), privateKey: Data(privateKey.bytes))
    }
}
