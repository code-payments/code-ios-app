//
//  ChatPhotoSend.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// How an uploaded photo goes out given the chat's current seal.
public enum ChatPhotoSend: Equatable {
    /// Plaintext, into a chat that doesn't encrypt.
    case plain(BlobID)
    /// Sealed, into the chat it was encrypted for.
    case sealed(SealedPhoto, ChatSeal)
    /// The photo was uploaded for a different encryption choice than the chat now makes.
    case mismatch

    public static func == (lhs: ChatPhotoSend, rhs: ChatPhotoSend) -> Bool {
        switch (lhs, rhs) {
        case (.plain(let a), .plain(let b)):             a == b
        case (.sealed(let a, _), .sealed(let b, _)):     a == b
        case (.mismatch, .mismatch):                     true
        case (.plain, _), (.sealed, _), (.mismatch, _):  false
        }
    }

    /// Matches `photo` to `seal`: a plaintext blob never goes into a chat that encrypts, nor a
    /// sealed one into a chat that doesn't or a different chat.
    public static func matching(_ photo: UploadedPhoto, seal: ChatSeal?, conversationID: ConversationID) -> ChatPhotoSend {
        switch (photo, seal) {
        case (.plain(let blobID), nil):
            .plain(blobID)
        case (.sealed(let sealed), let seal?) where seal.conversationID == conversationID:
            .sealed(sealed, seal)
        case (.plain, _?), (.sealed, _):
            .mismatch
        }
    }
}

private let logger = Logger(label: "flipcash.chat-photo-send")

extension FlipClient {

    /// Sends a photo the way it was uploaded, after checking the chat still decides the same way: a
    /// plaintext blob never goes into a chat that encrypts, nor a sealed one into a chat that doesn't.
    /// `seal` is the chat's current seal, nil when it sends in plaintext.
    public func sendMediaMessage(
        owner: KeyPair,
        conversationID: ConversationID,
        photo: UploadedPhoto,
        caption: String?,
        repliedTo: MessageID?,
        seal: ChatSeal?,
        clientMessageID: UUID
    ) async throws -> ConversationMessage {
        switch ChatPhotoSend.matching(photo, seal: seal, conversationID: conversationID) {
        case .plain(let blobID):
            return try await sendMediaMessage(owner: owner, conversationID: conversationID, blobID: blobID, caption: caption, repliedTo: repliedTo, clientMessageID: clientMessageID)
        case .sealed(let sealed, let seal):
            return try await sendSealedMediaMessage(owner: owner, conversationID: conversationID, photo: sealed, caption: caption, repliedTo: repliedTo, seal: seal, clientMessageID: clientMessageID)
        case .mismatch:
            logger.error("Photo was uploaded for a different encryption choice", metadata: [
                "conversationID": "\(conversationID)",
                "sealed": "\(seal != nil)",
            ])
            throw ErrorSendMessage.encryptionFailed
        }
    }
}
