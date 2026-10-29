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

    /// Replaces the minimum balance `role` requires in `rules`, the chat's current rules, and returns
    /// the chat's post-edit metadata. `amount` is in the listener minimum's currency; nil removes the
    /// chat minimum, leaving no separate speaker rule.
    func setMinimumBalance(
        conversationID: ConversationID,
        role: GroupBalanceRole,
        amount: FiatAmount?,
        in rules: ConversationRules
    ) async throws -> Conversation
}

/// Which of a group's minimum balances an edit replaces: the listener rule for ``join``, the
/// speaker rule for ``chat``.
nonisolated enum GroupBalanceRole: Hashable, Sendable {
    case join
    case chat
}

extension ConversationRulesEdit {
    /// `rules` with `role`'s minimum set to `amount` and every other rule as the group carries it,
    /// or nil when `rules` has no listener minimum, `amount` isn't in its currency, or `amount` is
    /// nil for ``GroupBalanceRole/join``, which can't be removed.
    init?(editing rules: ConversationRules, role: GroupBalanceRole, amount: FiatAmount?) {
        guard let requirements = GroupBalanceRequirements(rules), let join = requirements.join else { return nil }
        switch role {
        case .join:
            guard let amount else { return nil }
            self.init(editing: rules, listener: amount, speaker: requirements.speaker?.amount)
        case .chat:
            self.init(editing: rules, listener: join.amount, speaker: amount)
        }
    }
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

    func setMinimumBalance(
        conversationID: ConversationID,
        role: GroupBalanceRole,
        amount: FiatAmount?,
        in rules: ConversationRules
    ) async throws -> Conversation {
        guard let edit = ConversationRulesEdit(editing: rules, role: role, amount: amount) else {
            throw ErrorEditChat.invalidRules
        }
        return try await flipClient.editChat(
            owner: session.ownerKeyPair,
            conversationID: conversationID,
            title: nil,
            pictureBlobID: nil,
            rules: edit
        )
    }
}
