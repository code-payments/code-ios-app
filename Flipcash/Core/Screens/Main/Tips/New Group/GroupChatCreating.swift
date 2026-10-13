//
//  GroupChatCreating.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// The remote half of creating a group chat, in the order the flow calls it.
///
/// The owner is bound by the conformer, so the flow never handles keys — the seam
/// ``ProfilePictureUploading`` draws for the profile photo, for the same reason. The picture is
/// here rather than in a protocol of its own because the server requires it finalized *before*
/// `StartChat` will accept it, so the two calls are one ordered sequence rather than two the
/// screen would have to interleave.
protocol GroupChatCreating {

    /// Stores `data` and returns its blob, before the server has finalized it.
    func storeBlob(_ data: Data, mimeType: String) async throws -> BlobID

    /// Returns once the blob is servable, throwing `ErrorBlob.rejected` when it is refused and
    /// `ErrorBlob.timedOut` when it is still processing.
    func awaitBlobFinalization(blobID: BlobID) async throws

    /// Creates the group and returns its metadata as the server minted it.
    ///
    /// `idempotencyKey` identifies the *attempt*, not the parameters: the server derives the
    /// chat's identity from the caller and the key, so a retry carrying the key an earlier call
    /// already used returns the chat that call created — with `OK`, and with the title it sent.
    func startChat(
        title: String,
        pictureBlobID: BlobID?,
        rules: ConversationRules?,
        idempotencyKey: UUID
    ) async throws -> Conversation

    /// Creates a private group, which has no rules, under the same idempotency contract as
    /// ``startChat(title:pictureBlobID:rules:idempotencyKey:)``.
    func startPrivateChat(
        title: String,
        pictureBlobID: BlobID?,
        idempotencyKey: UUID
    ) async throws -> Conversation

    /// Generates a private group's chat key and stores the host's own envelope for it.
    func storeGroupKey(for conversationID: ConversationID) async throws
}

/// Creates on behalf of the signed-in owner.
struct SessionGroupChatCreator: GroupChatCreating {

    let session: Session
    let flipClient: FlipClient
    let groupKeys: GroupKeyEnvelopes

    func storeBlob(_ data: Data, mimeType: String) async throws -> BlobID {
        try await flipClient.storeBlob(data, mimeType: mimeType, owner: session.ownerKeyPair)
    }

    func awaitBlobFinalization(blobID: BlobID) async throws {
        try await flipClient.awaitBlobFinalization(blobID: blobID, owner: session.ownerKeyPair)
    }

    func startChat(
        title: String,
        pictureBlobID: BlobID?,
        rules: ConversationRules?,
        idempotencyKey: UUID
    ) async throws -> Conversation {
        try await flipClient.startChat(
            owner: session.ownerKeyPair,
            title: title,
            pictureBlobID: pictureBlobID,
            rules: rules,
            idempotencyKey: idempotencyKey
        )
    }

    func startPrivateChat(
        title: String,
        pictureBlobID: BlobID?,
        idempotencyKey: UUID
    ) async throws -> Conversation {
        try await flipClient.startPrivateChat(
            owner: session.ownerKeyPair,
            title: title,
            pictureBlobID: pictureBlobID,
            idempotencyKey: idempotencyKey
        )
    }

    func storeGroupKey(for conversationID: ConversationID) async throws {
        try await groupKeys.storeNewKey(for: conversationID)
    }
}
