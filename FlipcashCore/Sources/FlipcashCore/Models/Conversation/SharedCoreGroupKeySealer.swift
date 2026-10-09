//
//  SharedCoreGroupKeySealer.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import SharedCore

/// ``GroupKeySealing`` on shared-core's `ChatCipher`, the same implementation Android runs.
public struct SharedCoreGroupKeySealer: GroupKeySealing, @unchecked Sendable {

    /// The wire `KeyEnvelope.Scheme` this client reads and writes.
    public static let scheme = Flipcash_Chat_V1_KeyEnvelope.Scheme.x25519Xchacha20Poly1305

    private let cipher: any ChatCipher

    public init(cipher: any ChatCipher = DefaultChatCipher.shared) {
        self.cipher = cipher
    }

    public func newGroupKey() -> Data {
        SharedBytes.shared.data(bytes: cipher.doNewGroupKey())
    }

    public func wrap(groupKey: Data, owner: KeyPair, recipient: PublicKey, conversationID: ConversationID) throws -> ConversationKeyEnvelope {
        let bytes = SharedBytes.shared
        let payload = try cipher.wrapGroupKey(
            ownKeyPair: Self.keyPair(owner),
            recipientPk: bytes.byteArray(data: recipient.data),
            chatId: bytes.byteArray(data: conversationID.data),
            groupKey: bytes.byteArray(data: groupKey)
        )
        return ConversationKeyEnvelope(
            scheme: Self.scheme.rawValue,
            nonce: bytes.data(bytes: payload.nonce),
            ciphertext: bytes.data(bytes: payload.ciphertext)
        )
    }

    public func unwrap(_ envelope: ConversationKeyEnvelope, owner: KeyPair, wrapper: PublicKey, conversationID: ConversationID) throws -> Data {
        guard envelope.scheme == Self.scheme.rawValue else {
            throw UnsupportedKeyEnvelopeScheme()
        }
        let bytes = SharedBytes.shared
        let key = try cipher.unwrapGroupKey(
            ownKeyPair: Self.keyPair(owner),
            wrapperPk: bytes.byteArray(data: wrapper.data),
            chatId: bytes.byteArray(data: conversationID.data),
            envelope: EncryptedPayload(nonce: bytes.byteArray(data: envelope.nonce), ciphertext: bytes.byteArray(data: envelope.ciphertext))
        )
        return bytes.data(bytes: key)
    }

    private static func keyPair(_ owner: KeyPair) -> SharedCore.KeyPair {
        let bytes = SharedBytes.shared
        return SharedCore.KeyPair(
            publicKey: bytes.byteArray(data: owner.publicKey.data),
            privateKey: bytes.byteArray(data: owner.privateKey.data)
        )
    }
}

/// Thrown for a key envelope in a scheme this client cannot open.
public struct UnsupportedKeyEnvelopeScheme: Error {}
