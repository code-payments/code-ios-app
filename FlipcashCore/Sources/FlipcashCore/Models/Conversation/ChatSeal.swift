//
//  ChatSeal.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import SharedCore

/// One chat's end-to-end encryption: a DM's chat key, derived by both members and bound to the
/// chat and both public keys, or a private group's chat key, which every member holds. Encrypts
/// outgoing text and photos, and decrypts incoming `EncryptedContent` and the photo blobs it
/// references.
///
/// The cipher is shared-core's `ChatCipher` (scheme `X25519_XCHACHA20POLY1305` for DMs,
/// `CHAT_KEY_XCHACHA20POLY1305` for private groups), so both apps agree byte for byte. Stateless
/// after construction.
public struct ChatSeal: @unchecked Sendable {

    /// The wire `EncryptedContent.Scheme` this client reads and writes in a DM.
    public static let scheme = Flipcash_Messaging_V1_EncryptedContent.Scheme.x25519Xchacha20Poly1305

    /// The wire `EncryptedContent.Scheme` this client reads and writes in a private group.
    public static let groupScheme = Flipcash_Messaging_V1_EncryptedContent.Scheme.chatKeyXchacha20Poly1305

    private enum Mode {
        /// A DM: the derived pair key, with both public keys bound into every aad.
        case pair(chatKey: KotlinByteArray, ownPublicKey: KotlinByteArray, peerPublicKey: KotlinByteArray)
        /// A private group: the group key, with the sender's user ID bound into every aad.
        case group(groupKey: KotlinByteArray)
    }

    private let cipher: any ChatCipher
    private let mode: Mode
    private let chatID: KotlinByteArray
    private let selfUserID: UserID

    /// The chat this seal encrypts for.
    public let conversationID: ConversationID

    /// The wire scheme this seal writes and the only one it opens.
    public var scheme: Flipcash_Messaging_V1_EncryptedContent.Scheme {
        switch mode {
        case .pair: Self.scheme
        case .group: Self.groupScheme
        }
    }

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
        self.mode = .pair(
            chatKey: try cipher.chatKey(ownKeyPair: ownKeyPair, peerPublicKey: peer, chatId: chatID),
            ownPublicKey: ownPublicKey,
            peerPublicKey: peer
        )
        self.chatID = chatID
        self.selfUserID = selfUserID
        self.conversationID = conversationID
    }

    /// Seals and opens private group `conversationID` with its 32-byte `groupKey`.
    public init(cipher: any ChatCipher, groupKey: Data, conversationID: ConversationID, selfUserID: UserID) {
        let bytes = SharedBytes.shared
        self.cipher = cipher
        self.mode = .group(groupKey: bytes.byteArray(data: groupKey))
        self.chatID = bytes.byteArray(data: conversationID.data)
        self.selfUserID = selfUserID
        self.conversationID = conversationID
    }

    /// Encrypts `text` carrying `linkPreview`, as a reply to `repliedTo` when set, into the content
    /// to send in its place.
    public func seal(text: String, repliedTo: MessageID?, linkPreview: MessageLinkPreview? = nil) throws -> Flipcash_Messaging_V1_Content {
        try seal(.plaintext(text: text, repliedTo: repliedTo, linkPreview: linkPreview, sealed: true))
    }

    /// Encrypts a message carrying `photo`, with `caption` under it and as a reply to `repliedTo`
    /// when set, into the content to send in its place. `photo` must already be uploaded through
    /// ``encryptBlob(_:blobID:)`` and READY.
    public func seal(photo: SealedPhoto, caption: String?, repliedTo: MessageID?) throws -> Flipcash_Messaging_V1_Content {
        try seal(.plaintext(media: photo.media, caption: caption, repliedTo: repliedTo))
    }

    /// Encrypts a widget naming the payment request `id` into the content to send in its place.
    public func seal(paymentRequest id: PaymentRequestID) throws -> Flipcash_Messaging_V1_Content {
        try seal(.with {
            $0.widget = .with { $0.paymentRequest = .with { $0.paymentRequestID = id.proto } }
        })
    }

    /// Encrypts `plaintext` into the content to send in its place.
    func seal(_ plaintext: Flipcash_Messaging_V1_Content) throws -> Flipcash_Messaging_V1_Content {
        let bytes = SharedBytes.shared
        let content = bytes.byteArray(data: try plaintext.serializedData())
        let payload: EncryptedPayload
        switch mode {
        case .pair(let chatKey, let own, let peer):
            payload = try cipher.encrypt(content: content, chatKey: chatKey, senderPk: own, recipientPk: peer, chatId: chatID)
        case .group(let groupKey):
            payload = try cipher.encryptGroup(content: content, groupKey: groupKey, chatId: chatID, senderId: userID(selfUserID))
        }
        let scheme = self.scheme
        return .with {
            $0.encrypted = .with {
                $0.scheme = scheme
                $0.nonce = bytes.data(bytes: payload.nonce)
                $0.ciphertext = bytes.data(bytes: payload.ciphertext)
            }
        }
    }

    /// The blob to upload for `image`, the plaintext bytes of a photo this user sends as `blobID`:
    /// a fresh 24-byte nonce followed by the ciphertext and its tag.
    public func encryptBlob(_ image: Data, blobID: BlobID) throws -> Data {
        let bytes = SharedBytes.shared
        let plaintext = bytes.byteArray(data: image)
        let blob = bytes.byteArray(data: blobID.data)
        let sealed: KotlinByteArray
        switch mode {
        case .pair(let chatKey, let own, let peer):
            sealed = try cipher.encryptBlob(image: plaintext, chatKey: chatKey, senderPk: own, recipientPk: peer, chatId: chatID, blobId: blob)
        case .group(let groupKey):
            sealed = try cipher.encryptGroupBlob(image: plaintext, groupKey: groupKey, chatId: chatID, blobId: blob, senderId: userID(selfUserID))
        }
        return bytes.data(bytes: sealed)
    }

    /// The plaintext image in `blob`, the downloaded bytes of `blobID` that `sealed` describes.
    ///
    /// Throws ``BlobOpenFailure`` when the blob fails to authenticate or its plaintext is not the
    /// length the sender declared.
    public func decryptBlob(_ blob: Data, blobID: BlobID, sealed: SealedBlob) throws -> Data {
        let bytes = SharedBytes.shared
        let ciphertext = bytes.byteArray(data: blob)
        let blobIDBytes = bytes.byteArray(data: blobID.data)
        let image: KotlinByteArray
        do {
            switch mode {
            case .pair(let chatKey, let own, let peer):
                let isFromSelf = sealed.senderID == selfUserID
                image = try cipher.decryptBlob(
                    blob: ciphertext,
                    chatKey: chatKey,
                    senderPk: isFromSelf ? own : peer,
                    recipientPk: isFromSelf ? peer : own,
                    chatId: chatID,
                    blobId: blobIDBytes
                )
            case .group(let groupKey):
                image = try cipher.decryptGroupBlob(
                    blob: ciphertext,
                    groupKey: groupKey,
                    chatId: chatID,
                    blobId: blobIDBytes,
                    senderId: userID(sealed.senderID)
                )
            }
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
        guard scheme == self.scheme.rawValue, let senderID = message.senderID else {
            return message.opened(.failure(.unsupported))
        }

        let bytes = SharedBytes.shared
        let payload = EncryptedPayload(nonce: bytes.byteArray(data: nonce), ciphertext: bytes.byteArray(data: ciphertext))
        let plaintext: KotlinByteArray
        do {
            switch mode {
            case .pair(let chatKey, let own, let peer):
                let isFromSelf = senderID == selfUserID
                plaintext = try cipher.decrypt(
                    payload: payload,
                    chatKey: chatKey,
                    senderPk: isFromSelf ? own : peer,
                    recipientPk: isFromSelf ? peer : own,
                    chatId: chatID
                )
            case .group(let groupKey):
                plaintext = try cipher.decryptGroup(payload: payload, groupKey: groupKey, chatId: chatID, senderId: userID(senderID))
            }
        } catch {
            return message.opened(.failure(.authentication))
        }

        // Authenticated, so anything this client can't read, or a photo whose metadata breaks the
        // contract, is a newer or misbehaving client's content.
        guard let content = try? Flipcash_Messaging_V1_Content(serializedBytes: bytes.data(bytes: plaintext)),
              let readable = content.readable(senderID: senderID) else {
            return message.opened(.failure(.unsupported))
        }
        return message.opened(.success((readable.content, readable.repliedTo)), linkPreview: readable.linkPreview)
    }

    // MARK: - Payment request text -

    /// The wire `EncryptedPaymentRequestText.Scheme` a private group's request text is sealed with.
    public static let requestTextScheme = Flipcash_Paymentrequest_V1_EncryptedPaymentRequestText.Scheme.chatKeyXchacha20Poly1305

    /// Encrypts a request's `title` and `description`, created by this user, as the split's
    /// `encrypted` text. Throws in a DM, which has no group key.
    public func sealRequestText(title: String, description: String) throws -> GroupPaymentRequest.Text {
        guard case .group(let groupKey) = mode else { throw RequestTextFailure.notGroup }
        let bytes = SharedBytes.shared
        let text = Flipcash_Paymentrequest_V1_PaymentRequestText.with {
            $0.title = title
            $0.description_p = description
        }
        let payload = try cipher.encryptPaymentRequestText(
            text: bytes.byteArray(data: try text.serializedData()),
            groupKey: groupKey,
            chatId: chatID,
            creatorId: userID(selfUserID)
        )
        return .encrypted(
            scheme: Self.requestTextScheme.rawValue,
            nonce: bytes.data(bytes: payload.nonce),
            ciphertext: bytes.data(bytes: payload.ciphertext)
        )
    }

    /// Decrypts a request's encrypted text, created by `creator`. Throws when the scheme is not
    /// ``requestTextScheme``, the seal is a DM's, or the text fails to authenticate or decode.
    public func openRequestText(scheme: Int, nonce: Data, ciphertext: Data, creator: UserID?) throws -> (title: String, description: String) {
        guard case .group(let groupKey) = mode else { throw RequestTextFailure.notGroup }
        guard scheme == Self.requestTextScheme.rawValue, let creator else { throw RequestTextFailure.unsupported }
        let bytes = SharedBytes.shared
        let plaintext = try cipher.decryptPaymentRequestText(
            payload: EncryptedPayload(nonce: bytes.byteArray(data: nonce), ciphertext: bytes.byteArray(data: ciphertext)),
            groupKey: groupKey,
            chatId: chatID,
            creatorId: userID(creator)
        )
        let text = try Flipcash_Paymentrequest_V1_PaymentRequestText(serializedBytes: bytes.data(bytes: plaintext))
        return (text.title, text.description_p)
    }

    /// The raw `UserId.value` bytes the group aads bind.
    private func userID(_ id: UserID) -> KotlinByteArray {
        SharedBytes.shared.byteArray(data: id.data)
    }
}

/// Why a payment request's text could not be sealed or opened.
public enum RequestTextFailure: Error, Hashable, Sendable {
    /// The seal is a DM's; request text is sealed only under a group key.
    case notGroup
    /// The scheme is unknown or the request names no creator.
    case unsupported
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
public struct SealedPhoto: Hashable, Sendable, Codable {
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

    /// The plaintext content for `text` carrying `linkPreview`, wrapped as a reply to `repliedTo`
    /// when set. `sealed` says the content is about to be encrypted, which decides the image the
    /// preview may reference.
    static func plaintext(text: String, repliedTo: MessageID?, linkPreview: MessageLinkPreview? = nil, sealed: Bool = false) -> Self {
        let body = Self.with {
            $0.text = .with {
                $0.text = text
                if let linkPreview {
                    $0.linkPreviews = [linkPreview.proto(sealed: sealed)]
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

    /// The content, replied-to message and link preview of decrypted Text, Media, or a Reply of
    /// either sent by `senderID`; nil for any other type, or for media whose metadata breaks the
    /// contract.
    fileprivate func readable(senderID: UserID) -> (content: ConversationMessage.Content, repliedTo: MessageID?, linkPreview: MessageLinkPreview?)? {
        switch type {
        case .text(let text):
            return (.text(text.text), nil, .first(of: text, sealedBy: senderID))
        case .media(let media):
            return ConversationMessage.Content(sealed: media, senderID: senderID).map { ($0, nil, nil) }
        case .reply(let reply):
            guard reply.content.count == 1 else { return nil }
            let repliedTo = MessageID(reply.repliedMessageID)
            switch reply.content[0].type {
            case .text(let text):
                return (.text(text.text), repliedTo, .first(of: text, sealedBy: senderID))
            case .media(let media):
                return ConversationMessage.Content(sealed: media, senderID: senderID).map { ($0, repliedTo, nil) }
            case .cash, .system, .widget, .deleted, .encrypted, .reply, nil:
                return nil
            }
        case .widget(let widget):
            // A request is the one card a member seals; a profile share comes only from the server.
            switch widget.type {
            case .paymentRequest(let request) where request.hasPaymentRequestID:
                return (.widget(.paymentRequest(PaymentRequestID(request.paymentRequestID))), nil, nil)
            case .paymentRequest, .shareProfile, .poll, nil:
                return nil
            }
        case .cash, .system, .deleted, .encrypted, nil:
            return nil
        }
    }
}

extension ConversationMessage.Content {

    /// The `.media` content of a decrypted `MediaContent` sent by `senderID`, or nil when it breaks
    /// the encrypted-media contract: exactly one item that passes `MediaAttachment(sealed:senderID:)`.
    ///
    /// The dimensions are the sender's claim; the decoded image's own are authoritative once it loads.
    init?(sealed proto: Flipcash_Messaging_V1_MediaContent, senderID: UserID) {
        guard proto.items.count == 1,
              let attachment = MediaAttachment(sealed: proto.items[0], senderID: senderID) else { return nil }
        let caption = proto.caption.text
        self = .media([attachment], caption: caption.isEmpty ? nil : caption)
    }
}

extension MediaAttachment {

    /// The attachment a decrypted `Media` sent by `senderID` describes, or nil when it breaks the
    /// encrypted-media contract: exactly one ORIGINAL rendition, a blob id, and valid `BlobMetadata`
    /// describing an image.
    init?(sealed media: Flipcash_Blob_V1_Media, senderID: UserID) {
        guard media.renditions.count == 1 else { return nil }
        let rendition = media.renditions[0]
        guard rendition.role == .original,
              rendition.hasBlobID,
              rendition.blobID.value.count == 16,
              rendition.hasBlob,
              let image = Self.validImage(rendition.blob) else { return nil }
        self.init(
            blobID: BlobID(data: rendition.blobID.value),
            width: Int(image.width),
            height: Int(image.height),
            blurhash: image.blurhash.isEmpty ? nil : image.blurhash,
            sealed: SealedBlob(senderID: senderID, plaintextSize: Int(rendition.blob.sizeBytes))
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
