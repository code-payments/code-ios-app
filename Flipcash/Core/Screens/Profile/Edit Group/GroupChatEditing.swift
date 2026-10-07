//
//  GroupChatEditing.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// The remote half of editing a group chat, in the order the flow calls it.
///
/// The owner is bound by the conformer, so the flow never handles keys — the same seam
/// ``GroupChatCreating`` draws for creation, for the same reason. The blob calls sit here rather
/// than in a protocol of their own because `EditChat` will only accept a picture the server has
/// already finalized, so the two calls are one ordered sequence rather than two the screen would
/// have to interleave.
protocol GroupChatEditing {

    /// Stores `data` and returns its blob, before the server has finalized it.
    func storeBlob(_ data: Data, mimeType: String) async throws -> BlobID

    /// Returns once the blob is servable, throwing `ErrorBlob.rejected` when it is refused and
    /// `ErrorBlob.timedOut` when it is still processing.
    func awaitBlobFinalization(blobID: BlobID) async throws

    /// Applies a partial edit and returns the chat's post-edit metadata.
    ///
    /// Every field is independently optional and *unset means unchanged*, so a caller editing the
    /// name passes `description: .unchanged` and nil blobs and leaves the rest alone; `.clear`
    /// removes the description. Changing nothing is a no-op the server answers `OK`.
    func editChat(
        conversationID: ConversationID,
        title: String?,
        description: ConversationDescriptionEdit,
        pictureBlobID: BlobID?,
        coverPictureBlobID: BlobID?
    ) async throws -> Conversation

    /// Replaces the minimum balance `role` requires and returns the chat's post-edit metadata.
    func setMinimumBalance(
        conversationID: ConversationID,
        role: GroupBalanceRole,
        requirement: MinimumBalanceRequirement
    ) async throws -> Conversation
}

/// Which of a group's minimum balances an edit replaces: the listener rule for ``join``, the
/// speaker rule for ``chat``.
nonisolated enum GroupBalanceRole: Hashable, Sendable {
    case join
    case chat
}

/// Thrown by ``SessionGroupChatEditor/setMinimumBalance(conversationID:role:requirement:)`` until
/// the contract carries a way to change a group's rules.
enum ErrorSetGroupMinimumBalance: Error {
    case unavailable
}

/// Edits on behalf of the signed-in owner.
struct SessionGroupChatEditor: GroupChatEditing {

    let session: Session
    let flipClient: FlipClient

    func storeBlob(_ data: Data, mimeType: String) async throws -> BlobID {
        try await flipClient.storeBlob(data, mimeType: mimeType, owner: session.ownerKeyPair)
    }

    func awaitBlobFinalization(blobID: BlobID) async throws {
        try await flipClient.awaitBlobFinalization(blobID: blobID, owner: session.ownerKeyPair)
    }

    func editChat(
        conversationID: ConversationID,
        title: String?,
        description: ConversationDescriptionEdit,
        pictureBlobID: BlobID?,
        coverPictureBlobID: BlobID?
    ) async throws -> Conversation {
        try await flipClient.editChat(
            owner: session.ownerKeyPair,
            conversationID: conversationID,
            title: title,
            description: description,
            pictureBlobID: pictureBlobID,
            coverPictureBlobID: coverPictureBlobID
        )
    }

    // Stubbed: flipcash2-client-protocol 0.18.0 has no RPC that changes a group's rules after
    // `StartChat`, and `EditChatRequest` carries none. Replace this body with the FlipClient call
    // once the contract adds one, and seat the returned rules in `ConversationController.applyEdit`.
    func setMinimumBalance(
        conversationID: ConversationID,
        role: GroupBalanceRole,
        requirement: MinimumBalanceRequirement
    ) async throws -> Conversation {
        throw ErrorSetGroupMinimumBalance.unavailable
    }
}
