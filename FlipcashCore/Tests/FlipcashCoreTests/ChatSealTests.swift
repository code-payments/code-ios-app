//
//  ChatSealTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashAPI
import SharedCore
@testable import FlipcashCore

/// SharedCore exports its own `KeyPair`; these tests mean the app's.
private typealias KeyPair = FlipcashCore.KeyPair

@Suite("ChatSeal")
struct ChatSealTests {

    private let alice = KeyPair.generate()!
    private let bob = KeyPair.generate()!
    private let aliceID = UUID()
    private let bobID = UUID()
    private let chatID = ConversationID(data: Data(repeating: 7, count: 32))

    private func seal(owner: KeyPair, peer: KeyPair, selfID: UUID) throws -> ChatSeal {
        try ChatSeal(cipher: DefaultChatCipher.shared, owner: owner, peerPublicKey: peer.publicKey, conversationID: chatID, selfUserID: selfID)
    }

    /// The message `content` arrives as, sent by `sender`.
    private func message(_ content: Flipcash_Messaging_V1_Content, from sender: UUID) throws -> ConversationMessage {
        let proto = Flipcash_Messaging_V1_Message.with {
            $0.messageID = MessageID(value: 42).proto
            $0.senderID = sender.proto
            $0.content = [content]
        }
        return try #require(ConversationMessage(proto))
    }

    @Test("The peer decrypts what was sealed")
    func roundTrip() throws {
        let sealed = try seal(owner: alice, peer: bob, selfID: aliceID).seal(text: "hi bob", repliedTo: nil)
        let opened = try seal(owner: bob, peer: alice, selfID: bobID).open(message(sealed, from: aliceID))

        #expect(opened.content == .text("hi bob"))
        #expect(opened.decryptFailure == nil)
        #expect(opened.isEncrypted)
    }

    @Test("The sender decrypts their own message")
    func ownMessage() throws {
        let aliceSeal = try seal(owner: alice, peer: bob, selfID: aliceID)
        let opened = aliceSeal.open(try message(aliceSeal.seal(text: "note to self", repliedTo: nil), from: aliceID))

        #expect(opened.content == .text("note to self"))
    }

    @Test("A reply decrypts to its text and the message it quotes")
    func reply() throws {
        let sealed = try seal(owner: alice, peer: bob, selfID: aliceID).seal(text: "yes", repliedTo: MessageID(value: 9))
        let opened = try seal(owner: bob, peer: alice, selfID: bobID).open(message(sealed, from: aliceID))

        #expect(opened.content == .text("yes"))
        #expect(opened.repliedTo == MessageID(value: 9))
    }

    @Test("Tampered ciphertext fails authentication")
    func tampered() throws {
        var sealed = try seal(owner: alice, peer: bob, selfID: aliceID).seal(text: "hi", repliedTo: nil)
        sealed.encrypted.ciphertext[0] ^= 0xFF
        let opened = try seal(owner: bob, peer: alice, selfID: bobID).open(message(sealed, from: aliceID))

        #expect(opened.decryptFailure == .authentication)
        #expect(opened.isAwaitingDecryption == false)
    }

    @Test("A key that isn't the sender's fails authentication")
    func wrongKey() throws {
        let sealed = try seal(owner: alice, peer: bob, selfID: aliceID).seal(text: "hi", repliedTo: nil)
        let opened = try seal(owner: bob, peer: KeyPair.generate()!, selfID: bobID).open(message(sealed, from: aliceID))

        #expect(opened.decryptFailure == .authentication)
    }

    @Test("An unknown scheme is unsupported")
    func unknownScheme() throws {
        var sealed = try seal(owner: alice, peer: bob, selfID: aliceID).seal(text: "hi", repliedTo: nil)
        sealed.encrypted.scheme = .UNRECOGNIZED(99)
        let opened = try seal(owner: bob, peer: alice, selfID: bobID).open(message(sealed, from: aliceID))

        #expect(opened.decryptFailure == .unsupported)
    }

    @Test("Authenticated content of a type this client can't show is unsupported")
    func unknownContentType() throws {
        let bytes = SharedBytes.shared
        let plaintext = Flipcash_Messaging_V1_Content.with { $0.media = .init() }
        let owner = SharedCore.KeyPair(publicKey: bytes.byteArray(data: alice.publicKey.data), privateKey: bytes.byteArray(data: alice.privateKey.data))
        let chatKey = try DefaultChatCipher.shared.chatKey(ownKeyPair: owner, peerPublicKey: bytes.byteArray(data: bob.publicKey.data), chatId: bytes.byteArray(data: chatID.data))
        let payload = try DefaultChatCipher.shared.encrypt(
            content: bytes.byteArray(data: try plaintext.serializedData()),
            chatKey: chatKey,
            senderPk: bytes.byteArray(data: alice.publicKey.data),
            recipientPk: bytes.byteArray(data: bob.publicKey.data),
            chatId: bytes.byteArray(data: chatID.data)
        )
        let content = Flipcash_Messaging_V1_Content.with {
            $0.encrypted = .with {
                $0.scheme = ChatSeal.scheme
                $0.nonce = bytes.data(bytes: payload.nonce)
                $0.ciphertext = bytes.data(bytes: payload.ciphertext)
            }
        }
        let opened = try seal(owner: bob, peer: alice, selfID: bobID).open(message(content, from: aliceID))

        #expect(opened.decryptFailure == .unsupported)
    }

    @Test("Sealed content is EncryptedContent under the supported scheme")
    func wireShape() throws {
        let sealed = try seal(owner: alice, peer: bob, selfID: aliceID).seal(text: "hi", repliedTo: nil)

        guard case .encrypted(let encrypted) = sealed.type else {
            Issue.record("Expected encrypted content")
            return
        }
        #expect(encrypted.scheme == .x25519Xchacha20Poly1305)
        #expect(encrypted.nonce.count == 24)
    }
}
