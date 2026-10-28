//
//  ConversationInvite.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

// The invite wire shapes only. Deriving the token and id, and sealing and opening the envelopes, is
// shared core's, through ``InviteSealing``; the envelopes stay opaque bytes here, as
// ``ConversationKeyEnvelope`` does.

/// A group invite's 16-byte identifier, derived from its ``InviteToken``.
public struct InviteID: Hashable, Sendable {
    public let data: Data

    public init(data: Data) {
        self.data = data
    }

    init(_ proto: Flipcash_Chat_V1_InviteId) {
        self.data = proto.value
    }

    var proto: Flipcash_Chat_V1_InviteId {
        .with { $0.value = data }
    }
}

/// The 32-byte bearer token a link holder presents to read or join through an invite.
public struct InviteToken: Hashable, Sendable {
    public let data: Data

    public init(data: Data) {
        self.data = data
    }

    init(_ proto: Flipcash_Chat_V1_InviteToken) {
        self.data = proto.value
    }

    var proto: Flipcash_Chat_V1_InviteToken {
        .with { $0.value = data }
    }
}

/// The chat key wrapped under an invite's link secret and signed by the inviter.
public struct InviteKeyEnvelope: Hashable, Sendable {
    /// The proto `InviteKeyEnvelope.Scheme` raw value.
    public let scheme: Int
    public let nonce: Data
    public let ciphertext: Data
    /// The inviter's Ed25519 signature over the envelope.
    public let signature: Data

    public init(scheme: Int, nonce: Data, ciphertext: Data, signature: Data) {
        self.scheme = scheme
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.signature = signature
    }

    init(_ proto: Flipcash_Chat_V1_InviteKeyEnvelope) {
        self.init(scheme: proto.scheme.rawValue, nonce: proto.nonce, ciphertext: proto.ciphertext, signature: proto.signature)
    }

    var proto: Flipcash_Chat_V1_InviteKeyEnvelope {
        .with {
            $0.scheme = Flipcash_Chat_V1_InviteKeyEnvelope.Scheme(rawValue: scheme) ?? .unknown
            $0.nonce = nonce
            $0.ciphertext = ciphertext
            $0.signature = signature
        }
    }
}

/// The invite's link secret wrapped to its owner's key, so the inviter can show the link again.
public struct InviteSecretEnvelope: Hashable, Sendable {
    /// The proto `InviteSecretEnvelope.Scheme` raw value.
    public let scheme: Int
    public let nonce: Data
    public let ciphertext: Data

    public init(scheme: Int, nonce: Data, ciphertext: Data) {
        self.scheme = scheme
        self.nonce = nonce
        self.ciphertext = ciphertext
    }

    init(_ proto: Flipcash_Chat_V1_InviteSecretEnvelope) {
        self.init(scheme: proto.scheme.rawValue, nonce: proto.nonce, ciphertext: proto.ciphertext)
    }

    var proto: Flipcash_Chat_V1_InviteSecretEnvelope {
        .with {
            $0.scheme = Flipcash_Chat_V1_InviteSecretEnvelope.Scheme(rawValue: scheme) ?? .unknown
            $0.nonce = nonce
            $0.ciphertext = ciphertext
        }
    }
}

/// What a joiner presents with `joinChat` to enter a private group through an invite.
public struct InviteJoinParameters: Hashable, Sendable {
    public let token: InviteToken
    public let secretEnvelope: InviteSecretEnvelope

    public init(token: InviteToken, secretEnvelope: InviteSecretEnvelope) {
        self.token = token
        self.secretEnvelope = secretEnvelope
    }
}

/// A group invite as the server reports it.
public struct Invite: Hashable, Sendable {

    /// Whether the invite still admits users. Only ``active`` does.
    public enum Status: Hashable, Sendable {
        case unknown
        case active
        case exhausted
        case expired
        case revoked
    }

    public let id: InviteID
    public let conversationID: ConversationID
    public let createdBy: UserID?
    /// `0` means unlimited.
    public let maxUses: UInt32
    public let useCount: UInt32
    public let createdAt: Date?
    public let expiresAt: Date?
    public let status: Status
    /// The link secret wrapped to the creator. `nil` when the server sent none.
    public let secretEnvelope: InviteSecretEnvelope?

    public init(id: InviteID, conversationID: ConversationID, createdBy: UserID?, maxUses: UInt32, useCount: UInt32, createdAt: Date?, expiresAt: Date?, status: Status, secretEnvelope: InviteSecretEnvelope?) {
        self.id = id
        self.conversationID = conversationID
        self.createdBy = createdBy
        self.maxUses = maxUses
        self.useCount = useCount
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.status = status
        self.secretEnvelope = secretEnvelope
    }
}

extension Invite.Status {
    init(_ proto: Flipcash_Chat_V1_Invite.Status) {
        switch proto {
        case .active: self = .active
        case .exhausted: self = .exhausted
        case .expired: self = .expired
        case .revoked: self = .revoked
        case .unknown, .UNRECOGNIZED: self = .unknown
        }
    }
}

extension Invite {
    init(_ proto: Flipcash_Chat_V1_Invite) {
        self.init(
            id: InviteID(proto.inviteID),
            conversationID: ConversationID(proto.chatID),
            createdBy: proto.hasCreatedBy ? try? UUID(data: proto.createdBy.value) : nil,
            maxUses: proto.maxUses,
            useCount: proto.useCount,
            createdAt: proto.hasCreatedAt ? proto.createdAt.date : nil,
            expiresAt: proto.hasExpiresAt ? proto.expiresAt.date : nil,
            status: Status(proto.status),
            secretEnvelope: proto.hasSecretEnvelope ? InviteSecretEnvelope(proto.secretEnvelope) : nil
        )
    }
}

/// An invite-joined member's stored copy of the chat key, returned in place of their own envelope
/// until they replace it with one of their own.
public struct InviteKeyBundle: Hashable, Sendable {
    public let inviteID: InviteID
    public let keyEnvelope: InviteKeyEnvelope
    public let secretEnvelope: InviteSecretEnvelope

    public init(inviteID: InviteID, keyEnvelope: InviteKeyEnvelope, secretEnvelope: InviteSecretEnvelope) {
        self.inviteID = inviteID
        self.keyEnvelope = keyEnvelope
        self.secretEnvelope = secretEnvelope
    }
}

extension InviteKeyBundle {
    init(_ proto: Flipcash_Chat_V1_GetKeyEnvelopeResponse.InviteKeyBundle) {
        self.init(
            inviteID: InviteID(proto.inviteID),
            keyEnvelope: InviteKeyEnvelope(proto.keyEnvelope),
            secretEnvelope: InviteSecretEnvelope(proto.secretEnvelope)
        )
    }
}
