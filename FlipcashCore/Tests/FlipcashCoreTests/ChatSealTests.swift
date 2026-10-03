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

    // MARK: - Photos -

    private let blobID = BlobID(data: Data(repeating: 0xA5, count: 16))

    private func photo(sizeBytes: Int = 1234) -> SealedPhoto {
        SealedPhoto(blobID: blobID, mimeType: "image/jpeg", sizeBytes: sizeBytes, width: 640, height: 480, blurhash: "LEHV6nWB2yk8")
    }

    /// The decrypted `.media` attachment `content` carries.
    private func attachment(_ content: ConversationMessage.Content) throws -> (MediaAttachment, String?) {
        guard case .media(let attachments, let caption) = content, attachments.count == 1 else {
            Issue.record("Expected one media attachment, got \(content)")
            throw CancellationError()
        }
        return (attachments[0], caption)
    }

    @Test("The peer decrypts a sealed photo to its blob and sender-set metadata")
    func photoRoundTrip() throws {
        let sealed = try seal(owner: alice, peer: bob, selfID: aliceID).seal(photo: photo(), caption: nil, repliedTo: nil)
        let opened = try seal(owner: bob, peer: alice, selfID: bobID).open(message(sealed, from: aliceID))

        let (media, caption) = try attachment(opened.content)
        #expect(media == MediaAttachment(
            blobID: blobID, width: 640, height: 480, blurhash: "LEHV6nWB2yk8",
            sealed: SealedBlob(senderID: aliceID, plaintextSize: 1234)
        ))
        #expect(caption == nil)
        #expect(opened.repliedTo == nil)
        #expect(opened.decryptFailure == nil)
    }

    @Test("A sealed photo carries its caption and the message it replies to inside the ciphertext")
    func photoCaptionAndReply() throws {
        let sealed = try seal(owner: alice, peer: bob, selfID: aliceID).seal(photo: photo(), caption: "sunset", repliedTo: MessageID(value: 9))
        guard case .encrypted = sealed.type else {
            Issue.record("Expected encrypted content")
            return
        }
        let opened = try seal(owner: bob, peer: alice, selfID: bobID).open(message(sealed, from: aliceID))

        let (_, caption) = try attachment(opened.content)
        #expect(caption == "sunset")
        #expect(opened.repliedTo == MessageID(value: 9))
    }

    @Test("The sender's other device opens its own sealed photo")
    func photoOwnMessage() throws {
        let aliceSeal = try seal(owner: alice, peer: bob, selfID: aliceID)
        let opened = aliceSeal.open(try message(aliceSeal.seal(photo: photo(), caption: nil, repliedTo: nil), from: aliceID))

        let (media, _) = try attachment(opened.content)
        #expect(media.sealed?.senderID == aliceID)
    }

    @Test("Both members decrypt the blob the sender encrypted")
    func blobRoundTrip() throws {
        let image = Data((0..<4096).map { UInt8(truncatingIfNeeded: $0) })
        let sealedBlob = SealedBlob(senderID: aliceID, plaintextSize: image.count)
        let blob = try seal(owner: alice, peer: bob, selfID: aliceID).encryptBlob(image, blobID: blobID)

        #expect(blob.count == image.count + 24 + 16)
        #expect(try seal(owner: bob, peer: alice, selfID: bobID).decryptBlob(blob, blobID: blobID, sealed: sealedBlob) == image)
        #expect(try seal(owner: alice, peer: bob, selfID: aliceID).decryptBlob(blob, blobID: blobID, sealed: sealedBlob) == image)
    }

    @Test("A blob read under another blob id fails authentication")
    func blobWrongID() throws {
        let image = Data(repeating: 1, count: 100)
        let blob = try seal(owner: alice, peer: bob, selfID: aliceID).encryptBlob(image, blobID: blobID)
        let other = BlobID(data: Data(repeating: 0, count: 16))

        #expect(throws: BlobOpenFailure.authentication) {
            try seal(owner: bob, peer: alice, selfID: bobID).decryptBlob(blob, blobID: other, sealed: SealedBlob(senderID: aliceID, plaintextSize: 100))
        }
    }

    @Test("A blob attributed to the wrong sender fails authentication")
    func blobSwappedKeys() throws {
        let image = Data(repeating: 1, count: 100)
        let blob = try seal(owner: alice, peer: bob, selfID: aliceID).encryptBlob(image, blobID: blobID)

        // Bob reading it as his own upload puts the public keys in the aad the wrong way round.
        #expect(throws: BlobOpenFailure.authentication) {
            try seal(owner: bob, peer: alice, selfID: bobID).decryptBlob(blob, blobID: blobID, sealed: SealedBlob(senderID: bobID, plaintextSize: 100))
        }
    }

    @Test("A blob whose plaintext is not the declared size is rejected")
    func blobLengthMismatch() throws {
        let image = Data(repeating: 1, count: 100)
        let blob = try seal(owner: alice, peer: bob, selfID: aliceID).encryptBlob(image, blobID: blobID)

        #expect(throws: BlobOpenFailure.length) {
            try seal(owner: bob, peer: alice, selfID: bobID).decryptBlob(blob, blobID: blobID, sealed: SealedBlob(senderID: aliceID, plaintextSize: 99))
        }
    }

    /// The opened result of `media`, sealed by Alice by hand so it can break the contract.
    private func openHandSealed(_ media: Flipcash_Messaging_V1_MediaContent) throws -> ConversationMessage {
        let bytes = SharedBytes.shared
        let plaintext = Flipcash_Messaging_V1_Content.with { $0.media = media }
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
        return try seal(owner: bob, peer: alice, selfID: bobID).open(message(content, from: aliceID))
    }

    /// A valid sealed photo's `MediaContent`, for the validation cases to break one field of.
    private var validMedia: Flipcash_Messaging_V1_MediaContent {
        .with { $0.items = [photo().media] }
    }

    @Test("Hand-sealed valid media opens, so the cases below fail for their one broken field")
    func handSealedValid() throws {
        #expect(try openHandSealed(validMedia).decryptFailure == nil)
    }

    @Test(
        "Media whose metadata breaks the contract is unsupported",
        arguments: [
            "zero size", "non-image mime", "empty mime", "long mime", "zero width", "zero height",
            "long blurhash", "no metadata", "no blob id", "short blob id", "not original",
            "two renditions", "two items", "no items", "no image metadata",
        ]
    )
    func invalidMediaIsUnsupported(_ breakage: String) throws {
        var media = validMedia
        switch breakage {
        case "zero size":         media.items[0].renditions[0].blob.sizeBytes = 0
        case "non-image mime":    media.items[0].renditions[0].blob.mimeType = "video/mp4"
        case "empty mime":        media.items[0].renditions[0].blob.mimeType = ""
        case "long mime":         media.items[0].renditions[0].blob.mimeType = "image/" + String(repeating: "x", count: 250)
        case "zero width":        media.items[0].renditions[0].blob.image.width = 0
        case "zero height":       media.items[0].renditions[0].blob.image.height = 0
        case "long blurhash":     media.items[0].renditions[0].blob.image.blurhash = String(repeating: "L", count: 65)
        case "no metadata":       media.items[0].renditions[0].clearBlob()
        case "no blob id":        media.items[0].renditions[0].clearBlobID()
        case "short blob id":     media.items[0].renditions[0].blobID.value = Data([1, 2, 3])
        case "not original":      media.items[0].renditions[0].role = .unknown
        case "two renditions":    media.items[0].renditions.append(media.items[0].renditions[0])
        case "two items":         media.items.append(media.items[0])
        case "no items":          media.items = []
        case "no image metadata": media.items[0].renditions[0].blob.kind = nil
        default:                  Issue.record("Unknown breakage \(breakage)")
        }

        #expect(try openHandSealed(media).decryptFailure == .unsupported)
    }

    @Test("A download URL inside sealed media is ignored")
    func downloadURLIgnored() throws {
        var media = validMedia
        media.items[0].renditions[0].blob.downloadURL = .with { $0.url = "https://example.com/x" }
        #expect(try openHandSealed(media).decryptFailure == nil)
    }
}
