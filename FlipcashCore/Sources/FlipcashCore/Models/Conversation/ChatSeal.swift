//
//  ChatSeal.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import SharedCore

/// One DM's end-to-end encryption: the chat key both members derive, bound to the chat and both
/// public keys. Encrypts outgoing text and decrypts incoming `EncryptedContent`.
///
/// The cipher is shared-core's `ChatCipher` (scheme `X25519_XCHACHA20POLY1305`), so both apps agree
/// byte for byte. Stateless after construction.
public struct ChatSeal: @unchecked Sendable {

    /// The wire `EncryptedContent.Scheme` this client reads and writes.
    public static let scheme = Flipcash_Messaging_V1_EncryptedContent.Scheme.x25519Xchacha20Poly1305

    private let cipher: any ChatCipher
    private let chatKey: KotlinByteArray
    private let ownPublicKey: KotlinByteArray
    private let peerPublicKey: KotlinByteArray
    private let chatID: KotlinByteArray
    private let selfUserID: UserID

    /// Derives the chat key for `owner` and `peerPublicKey` in `conversationID`.
    ///
    /// Throws when shared-core rejects the peer key (not a valid point, low-order).
    public init(
        cipher: any ChatCipher,
        owner: KeyPair,
        peerPublicKey: PublicKey,
        conversationID: ConversationID,
        selfUserID: UserID
    ) throws {
        let bytes = SharedBytes.shared
        let ownPublicKey = bytes.byteArray(data: owner.publicKey.data)
        let ownKeyPair = SharedCore.KeyPair(publicKey: ownPublicKey, privateKey: bytes.byteArray(data: owner.privateKey.data))
        let chatID = bytes.byteArray(data: conversationID.data)
        let peer = bytes.byteArray(data: peerPublicKey.data)
        self.cipher = cipher
        self.chatKey = try cipher.chatKey(ownKeyPair: ownKeyPair, peerPublicKey: peer, chatId: chatID)
        self.ownPublicKey = ownPublicKey
        self.peerPublicKey = peer
        self.chatID = chatID
        self.selfUserID = selfUserID
    }

    /// Encrypts `text`, as a reply to `repliedTo` when set, into the content to send in its place.
    public func seal(text: String, repliedTo: MessageID?) throws -> Flipcash_Messaging_V1_Content {
        let plaintext = Flipcash_Messaging_V1_Content.plaintext(text: text, repliedTo: repliedTo)
        let payload = try cipher.encrypt(
            content: SharedBytes.shared.byteArray(data: try plaintext.serializedData()),
            chatKey: chatKey,
            senderPk: ownPublicKey,
            recipientPk: peerPublicKey,
            chatId: chatID
        )
        return .with {
            $0.encrypted = .with {
                $0.scheme = Self.scheme
                $0.nonce = SharedBytes.shared.data(bytes: payload.nonce)
                $0.ciphertext = SharedBytes.shared.data(bytes: payload.ciphertext)
            }
        }
    }

    /// `message` with its content decrypted, or carrying why it could not be. A message that isn't
    /// `.encrypted` comes back unchanged.
    public func open(_ message: ConversationMessage) -> ConversationMessage {
        guard case .encrypted(let scheme, let nonce, let ciphertext) = message.content else { return message }
        guard scheme == Self.scheme.rawValue else { return message.opened(.failure(.unsupported)) }

        let isFromSelf = message.senderID == selfUserID
        let bytes = SharedBytes.shared
        let plaintext: KotlinByteArray
        do {
            plaintext = try cipher.decrypt(
                payload: EncryptedPayload(nonce: bytes.byteArray(data: nonce), ciphertext: bytes.byteArray(data: ciphertext)),
                chatKey: chatKey,
                senderPk: isFromSelf ? ownPublicKey : peerPublicKey,
                recipientPk: isFromSelf ? peerPublicKey : ownPublicKey,
                chatId: chatID
            )
        } catch {
            return message.opened(.failure(.authentication))
        }

        // Authenticated, so anything this client can't read is a newer client's content.
        guard let content = try? Flipcash_Messaging_V1_Content(serializedBytes: bytes.data(bytes: plaintext)),
              let readable = content.readableText else {
            return message.opened(.failure(.unsupported))
        }
        return message.opened(.success(readable))
    }
}

extension Flipcash_Messaging_V1_Content {

    /// The plaintext content for `text`, wrapped as a reply to `repliedTo` when set.
    static func plaintext(text: String, repliedTo: MessageID?) -> Self {
        let body = Self.with { $0.text = .with { $0.text = text } }
        guard let repliedTo else { return body }
        return .with {
            $0.reply = .with {
                $0.repliedMessageID = repliedTo.proto
                $0.content = [body]
            }
        }
    }

    /// The text and replied-to message of decrypted Text or Reply(Text) content; nil for any other.
    fileprivate var readableText: (text: String, repliedTo: MessageID?)? {
        switch type {
        case .text(let text):
            return (text.text, nil)
        case .reply(let reply):
            guard reply.content.count == 1, case .text(let text) = reply.content[0].type else { return nil }
            return (text.text, MessageID(reply.repliedMessageID))
        case .cash, .media, .system, .deleted, .encrypted, nil:
            return nil
        }
    }
}
