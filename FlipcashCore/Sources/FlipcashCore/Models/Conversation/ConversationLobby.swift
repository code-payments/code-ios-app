//
//  ConversationLobby.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

/// A wrapped chat key, carried as the opaque bytes the server stores. This client neither wraps
/// nor unwraps it: key wrapping is a cross-platform shared-logic hotspot that is not implemented
/// yet, so the scheme stays a raw value (like ``ConversationMessageContent/encrypted``) rather
/// than an enum this client would have to act on.
public struct ConversationKeyEnvelope: Hashable, Sendable {
    /// The proto `KeyEnvelope.Scheme` raw value.
    public let scheme: Int
    public let nonce: Data
    public let ciphertext: Data

    public init(scheme: Int, nonce: Data, ciphertext: Data) {
        self.scheme = scheme
        self.nonce = nonce
        self.ciphertext = ciphertext
    }
}

extension ConversationKeyEnvelope {
    init(_ proto: Flipcash_Chat_V1_KeyEnvelope) {
        self.init(scheme: proto.scheme.rawValue, nonce: proto.nonce, ciphertext: proto.ciphertext)
    }

    var proto: Flipcash_Chat_V1_KeyEnvelope {
        .with {
            $0.scheme = Flipcash_Chat_V1_KeyEnvelope.Scheme(rawValue: scheme) ?? .unknown
            $0.nonce = nonce
            $0.ciphertext = ciphertext
        }
    }
}

/// A user waiting in a private chat's lobby for an admin to admit them.
public struct LobbyMember: Sendable {
    /// The waiting user's profile. `nil` when it does not parse.
    public let profile: Profile?
    /// The key an admitting member wraps the chat key to.
    public let publicKey: PublicKey
    public let enteredAt: Date?

    public var userID: UserID? { profile?.userID }

    public init(profile: Profile?, publicKey: PublicKey, enteredAt: Date?) {
        self.profile = profile
        self.publicKey = publicKey
        self.enteredAt = enteredAt
    }
}

extension LobbyMember {
    /// Nil when the public key does not parse: without it the member cannot be admitted.
    init?(_ proto: Flipcash_Chat_V1_LobbyMember) {
        guard let publicKey = try? PublicKey(proto.publicKey.value) else { return nil }
        self.init(
            profile: try? Profile(proto.userProfile),
            publicKey: publicKey,
            enteredAt: proto.hasEnteredAt ? proto.enteredAt.date : nil
        )
    }
}

/// A private chat the signed-in user has entered the lobby of and not yet been admitted to.
public struct Lobby: Sendable {
    public let conversation: Conversation
    public let enteredAt: Date?

    public init(conversation: Conversation, enteredAt: Date?) {
        self.conversation = conversation
        self.enteredAt = enteredAt
    }
}

extension Lobby {
    /// Nil when the response carries no chat metadata.
    init?(_ proto: Flipcash_Chat_V1_Lobby) {
        guard proto.hasChat else { return nil }
        self.init(
            conversation: Conversation(proto.chat),
            enteredAt: proto.hasEnteredAt ? proto.enteredAt.date : nil
        )
    }
}

/// One change to a private chat's lobby, delivered to its admitting members.
public enum LobbyUpdate: Sendable {
    case memberEntered(LobbyMember)
    case memberLeft(userID: UserID)
}

extension LobbyUpdate {
    /// Nil for a kind this client does not know, or a member or user id that does not parse.
    init?(_ proto: Flipcash_Chat_V1_LobbyUpdate) {
        switch proto.kind {
        case .memberEntered(let entered):
            guard entered.hasMember, let member = LobbyMember(entered.member) else { return nil }
            self = .memberEntered(member)
        case .memberLeft(let left):
            guard let userID = try? UUID(data: left.userID.value) else { return nil }
            self = .memberLeft(userID: userID)
        case nil:
            return nil
        }
    }
}
