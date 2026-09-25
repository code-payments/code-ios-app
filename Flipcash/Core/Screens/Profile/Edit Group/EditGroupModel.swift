//
//  EditGroupModel.swift
//  Flipcash
//

import UIKit
import FlipcashCore

/// Thrown when a save runs against a form that has nothing the server would accept. Both screens
/// disable their button in that state, so this is a programming error rather than something either
/// puts in front of the user.
struct EditGroupIncomplete: Error {}

/// What a single group edit holds while it is being made, and the one call that submits it (node
/// 10187:110373).
///
/// One instance per edit rather than one shared across the Edit list's rows: `EditChat` treats
/// every field as *unset means unchanged*, so a name edit and a picture edit are two independent
/// partial updates. ``saveTitle(for:using:)`` and ``savePicture(for:using:)`` each send only their
/// own field, which is what keeps editing the name from clearing the picture.
@MainActor
@Observable
final class EditGroupModel {

    /// The title as typed. Submitted through ``GroupTitleValidator``, never raw — the contract caps
    /// `Title.value` at 1...64 and the server rejects anything outside it.
    var title: String

    /// The picture the user picked, before it is encoded or uploaded. Nil until they pick one; the
    /// group's existing picture is drawn by the screen and never resubmitted.
    private(set) var picture: UIImage?

    /// Whether a save is in flight, so the button stops taking taps.
    private(set) var isSaving = false

    /// The blob the picture landed in, held across retries: the reservation signs the byte count,
    /// so a retry that re-encoded would be storing a second copy of a picture the server already
    /// has. Mirrors ``NewPublicGroupModel/reservedBlobID``.
    private(set) var reservedBlobID: BlobID?

    /// Cap on the encoded picture, matching the profile photo's and the new-group form's.
    private static let maxUploadBytes = 2 * 1_024 * 1_024

    private let validator = GroupTitleValidator()

    /// Seeded with the title the group carries, so the name field opens on what it is about to
    /// replace rather than on a blank.
    init(title: String = "") {
        self.title = title
    }

    // MARK: - Form state -

    func select(picture: UIImage) {
        self.picture = picture
        // A different picture is a different upload: the held reservation signed the previous
        // image's byte count and would upload that one instead.
        reservedBlobID = nil
    }

    /// The title as it would be submitted, or nil while the field holds nothing the server accepts.
    var validatedTitle: String? {
        validator.validate(title)
    }

    /// How many more Unicode scalars the title field accepts.
    var remainingTitleScalars: Int {
        validator.remaining(in: title)
    }

    /// Whether Save is enabled for the name: a title the server will take, actually different from
    /// the one the group carries, and nothing already in flight.
    ///
    /// Re-sending the current title spends a moderation round trip to change nothing, the same
    /// reason ``ProfileNameScreen`` holds its Save shut on an unchanged name.
    func canSaveTitle(currentTitle: String?) -> Bool {
        guard !isSaving, let validatedTitle else { return false }
        return validatedTitle != currentTitle
    }

    /// Whether Save is enabled for the picture: one has been picked and nothing is in flight. The
    /// group's existing picture is not a submission, so this stays shut until the user picks.
    var canSavePicture: Bool {
        !isSaving && picture != nil
    }

    // MARK: - Save -

    /// Sends the title alone and returns the chat's post-edit metadata.
    ///
    /// `pictureBlobID` is nil by construction: unset means unchanged, so a name edit leaves the
    /// group's picture exactly where it was.
    func saveTitle(for conversationID: ConversationID, using editor: some GroupChatEditing) async throws -> Conversation {
        guard let title = validatedTitle else {
            throw EditGroupIncomplete()
        }

        isSaving = true
        defer { isSaving = false }

        return try await Self.tracked(.name) {
            try await editor.editChat(
                conversationID: conversationID,
                title: title,
                pictureBlobID: nil
            )
        }
    }

    /// Uploads the picked picture, waits for the server to finalize it, then sends it alone and
    /// returns the chat's post-edit metadata.
    ///
    /// The wait is not optional: `EditChat` answers `PICTURE_BLOB_NOT_ACCEPTED` for a blob that is
    /// still pending or processing, so the finalization has to land before the edit is sent.
    /// `title` is nil by construction, leaving the group's name untouched.
    func savePicture(for conversationID: ConversationID, using editor: some GroupChatEditing) async throws -> Conversation {
        guard picture != nil else {
            throw EditGroupIncomplete()
        }

        isSaving = true
        defer { isSaving = false }

        let blobID = try await uploadPicture(using: editor)

        return try await Self.tracked(.picture) {
            try await editor.editChat(
                conversationID: conversationID,
                title: nil,
                pictureBlobID: blobID
            )
        }
    }

    /// Runs the `EditChat` call and reports what it returned as a `field` edit.
    private static func tracked(
        _ field: GroupField,
        _ editChat: () async throws -> Conversation
    ) async throws -> Conversation {
        do {
            let conversation = try await editChat()
            Analytics.groupEdited(field: field, error: nil)
            return conversation
        } catch {
            Analytics.groupEdited(field: field, error: error)
            throw error
        }
    }

    /// Stores and finalizes the picture, returning the blob `EditChat` should carry. A rejected
    /// blob clears the reservation so a different picture starts clean.
    private func uploadPicture(using editor: some GroupChatEditing) async throws -> BlobID {
        if reservedBlobID == nil, let picture {
            // Encode before storing: the reservation signs the byte count, so the bytes may not
            // change afterwards.
            let data = try await ImageEncoder.encodeForUpload(picture, maxBytes: Self.maxUploadBytes)
            reservedBlobID = try await editor.storeBlob(data, mimeType: "image/jpeg")
        }

        guard let blobID = reservedBlobID else {
            throw EditGroupIncomplete()
        }

        do {
            try await editor.awaitBlobFinalization(blobID: blobID)
        } catch ErrorBlob.rejected(let reason) {
            reservedBlobID = nil
            throw ErrorBlob.rejected(reason)
        }

        return blobID
    }
}
