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
    /// Both fields are independently optional and *unset means unchanged*, so a caller editing the
    /// name passes `pictureBlobID: nil` and leaves the picture alone. Passing neither is a no-op
    /// the server answers `OK`.
    func editChat(
        conversationID: ConversationID,
        title: String?,
        pictureBlobID: BlobID?
    ) async throws -> Conversation
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
        pictureBlobID: BlobID?
    ) async throws -> Conversation {
        try await flipClient.editChat(
            owner: session.ownerKeyPair,
            conversationID: conversationID,
            title: title,
            pictureBlobID: pictureBlobID
        )
    }
}
