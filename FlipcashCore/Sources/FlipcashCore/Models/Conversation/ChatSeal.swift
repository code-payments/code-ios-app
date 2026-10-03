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
/// public keys. Encrypts outgoing text and photos, and decrypts incoming `EncryptedContent` and the
/// photo blobs it references.
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

    /// The chat this seal encrypts for.
    public let conversationID: ConversationID

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
        self.conversationID = conversationID
    }

    /// Encrypts `text`, as a reply to `repliedTo` when set, into the content to send in its place.
    public func seal(text: String, repliedTo: MessageID?) throws -> Flipcash_Messaging_V1_Content {
        try seal(.plaintext(text: text, repliedTo: repliedTo))
    }

    /// Encrypts a message carrying `photo`, with `caption` under it and as a reply to `repliedTo`
    /// when set, into the content to send in its place. `photo` must already be uploaded through
    /// ``encryptBlob(_:blobID:)`` and READY.
    public func seal(photo: SealedPhoto, caption: String?, repliedTo: MessageID?) throws -> Flipcash_Messaging_V1_Content {
        try seal(.plaintext(media: photo.media, caption: caption, repliedTo: repliedTo))
    }

    private func seal(_ plaintext: Flipcash_Messaging_V1_Content) throws -> Flipcash_Messaging_V1_Content {
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

    /// The blob to upload for `image`, the plaintext bytes of a photo this user sends as `blobID`:
    /// a fresh 24-byte nonce followed by the ciphertext and its tag.
    public func encryptBlob(_ image: Data, blobID: BlobID) throws -> Data {
        let bytes = SharedBytes.shared
        let blob = try cipher.encryptBlob(
            image: bytes.byteArray(data: image),
            chatKey: chatKey,
            senderPk: ownPublicKey,
            recipientPk: peerPublicKey,
            chatId: chatID,
            blobId: bytes.byteArray(data: blobID.data)
        )
        return bytes.data(bytes: blob)
    }

    /// The plaintext image in `blob`, the downloaded bytes of `blobID` that `sealed` describes.
    ///
    /// Throws ``BlobOpenFailure`` when the blob fails to authenticate or its plaintext is not the
    /// length the sender declared.
    public func decryptBlob(_ blob: Data, blobID: BlobID, sealed: SealedBlob) throws -> Data {
        let bytes = SharedBytes.shared
        let isFromSelf = sealed.senderID == selfUserID
        let image: KotlinByteArray
        do {
            image = try cipher.decryptBlob(
                blob: bytes.byteArray(data: blob),
                chatKey: chatKey,
                senderPk: isFromSelf ? ownPublicKey : peerPublicKey,
                recipientPk: isFromSelf ? peerPublicKey : ownPublicKey,
                chatId: chatID,
                blobId: bytes.byteArray(data: blobID.data)
            )
        } catch {
            throw BlobOpenFailure.authentication
        }
        let data = bytes.data(bytes: image)
        guard data.count == sealed.plaintextSize else { throw BlobOpenFailure.length }
        return data
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

        // Authenticated, so anything this client can't read, or a photo whose metadata breaks the
        // contract, is a newer or misbehaving client's content.
        guard let content = try? Flipcash_Messaging_V1_Content(serializedBytes: bytes.data(bytes: plaintext)),
              let senderID = message.senderID,
              let readable = content.readable(senderID: senderID) else {
            return message.opened(.failure(.unsupported))
        }
        return message.opened(.success(readable))
    }
}

/// Why a photo blob could not be decrypted; either way the photo draws as unsupported.
public enum BlobOpenFailure: Error, Hashable, Sendable {
    /// The blob failed to authenticate under the chat key and its aad.
    case authentication
    /// The decrypted image is not the length the sender declared.
    case length
    /// The decrypted bytes don't decode as an image.
    case undecodable
}

/// A photo uploaded encrypted for a chat, with the plaintext metadata its sealed message carries.
public struct SealedPhoto: Hashable, Sendable {
    /// The encrypted blob, READY before the message is sent.
    public let blobID: BlobID
    /// The plaintext image's MIME type, always an `image/` type.
    public let mimeType: String
    /// The plaintext image's length in bytes.
    public let sizeBytes: Int
    /// Pixel width of the plaintext image.
    public let width: Int
    /// Pixel height of the plaintext image.
    public let height: Int
    /// The plaintext image's BlurHash, at most 64 characters.
    public let blurhash: String

    public init(blobID: BlobID, mimeType: String, sizeBytes: Int, width: Int, height: Int, blurhash: String) {
        self.blobID = blobID
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.width = width
        self.height = height
        self.blurhash = blurhash
    }

    /// The single-ORIGINAL `Media` the sealed message carries, with the sender-set metadata the
    /// server never sees and no download URL.
    var media: Flipcash_Blob_V1_Media {
        .with {
            $0.renditions = [.with {
                $0.role = .original
                $0.blobID = .with { $0.value = blobID.data }
                $0.blob = .with {
                    $0.mimeType = mimeType
                    $0.sizeBytes = UInt64(sizeBytes)
                    $0.image = .with {
                        $0.width = UInt32(width)
                        $0.height = UInt32(height)
                        $0.blurhash = blurhash
                    }
                }
            }]
        }
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

    /// The media content for `media`, with `caption` under it, wrapped as a reply to `repliedTo`
    /// when set. A reply nests the media one level deeper on the wire.
    static func plaintext(media: Flipcash_Blob_V1_Media, caption: String?, repliedTo: MessageID?) -> Self {
        let body = Self.with {
            $0.media = .with {
                $0.items = [media]
                if let caption {
                    $0.caption = .with { $0.text = caption }
                }
            }
        }
        guard let repliedTo else { return body }
        return .with {
            $0.reply = .with {
                $0.repliedMessageID = repliedTo.proto
                $0.content = [body]
            }
        }
    }

    /// The content and replied-to message of decrypted Text, Media, or a Reply of either sent by
    /// `senderID`; nil for any other type, or for media whose metadata breaks the contract.
    fileprivate func readable(senderID: UserID) -> (content: ConversationMessage.Content, repliedTo: MessageID?)? {
        switch type {
        case .text(let text):
            return (.text(text.text), nil)
        case .media(let media):
            return ConversationMessage.Content(sealed: media, senderID: senderID).map { ($0, nil) }
        case .reply(let reply):
            guard reply.content.count == 1 else { return nil }
            let repliedTo = MessageID(reply.repliedMessageID)
            switch reply.content[0].type {
            case .text(let text):
                return (.text(text.text), repliedTo)
            case .media(let media):
                return ConversationMessage.Content(sealed: media, senderID: senderID).map { ($0, repliedTo) }
            case .cash, .system, .widget, .deleted, .encrypted, .reply, nil:
                return nil
            }
        case .cash, .system, .widget, .deleted, .encrypted, nil:
            return nil
        }
    }
}

extension ConversationMessage.Content {

    /// The `.media` content of a decrypted `MediaContent` sent by `senderID`, or nil when it breaks
    /// the encrypted-media contract: exactly one item with exactly one ORIGINAL rendition, a blob id,
    /// and valid `BlobMetadata` describing an image.
    ///
    /// The dimensions are the sender's claim; the decoded image's own are authoritative once it loads.
    init?(sealed proto: Flipcash_Messaging_V1_MediaContent, senderID: UserID) {
        guard proto.items.count == 1,
              proto.items[0].renditions.count == 1 else { return nil }
        let rendition = proto.items[0].renditions[0]
        guard rendition.role == .original,
              rendition.hasBlobID,
              rendition.blobID.value.count == 16,
              rendition.hasBlob,
              let image = Self.validImage(rendition.blob) else { return nil }
        let caption = proto.caption.text
        self = .media(
            [MediaAttachment(
                blobID: BlobID(data: rendition.blobID.value),
                width: Int(image.width),
                height: Int(image.height),
                blurhash: image.blurhash.isEmpty ? nil : image.blurhash,
                sealed: SealedBlob(senderID: senderID, plaintextSize: Int(rendition.blob.sizeBytes))
            )],
            caption: caption.isEmpty ? nil : caption
        )
    }

    /// `metadata`'s image description when it passes the `blob.v1.BlobMetadata` rules for an image.
    private static func validImage(_ metadata: Flipcash_Blob_V1_BlobMetadata) -> Flipcash_Blob_V1_ImageMetadata? {
        let mimeType = metadata.mimeType
        guard (1...255).contains(mimeType.unicodeScalars.count),
              mimeType.lowercased().hasPrefix("image/"),
              metadata.sizeBytes >= 1,
              metadata.sizeBytes <= UInt64(Int.max) else { return nil }
        switch metadata.kind {
        case .image(let image):
            guard image.width >= 1, image.height >= 1, image.blurhash.unicodeScalars.count <= 64 else { return nil }
            return image
        case .encrypted, nil:
            return nil
        }
    }
}
