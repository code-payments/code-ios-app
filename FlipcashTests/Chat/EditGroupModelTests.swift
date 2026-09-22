//
//  EditGroupModelTests.swift
//  FlipcashTests
//

import Foundation
import UIKit
import Testing
@testable import Flipcash
import FlipcashCore

@MainActor
@Suite("Group edit form")
struct EditGroupModelTests {

    // MARK: - Doubles -

    /// Records what the form asked of the server, and answers with whatever the test set.
    private final class SpyEditor: GroupChatEditing {

        private(set) var editCalls: [(title: String?, blobID: BlobID?)] = []
        private(set) var storeBlobCallCount = 0
        private(set) var finalizationCallCount = 0

        /// The order the seam was called in, so a test can assert the blob was finalized *before*
        /// the edit was sent rather than merely that both happened.
        private(set) var callOrder: [String] = []

        /// Thrown by the next `editChat`, then cleared — so a test can fail one attempt and let the
        /// retry through.
        var nextEditError: Error?
        /// Thrown by the next `awaitBlobFinalization`, then cleared.
        var nextFinalizationError: Error?

        func storeBlob(_ data: Data, mimeType: String) async throws -> BlobID {
            storeBlobCallCount += 1
            callOrder.append("store")
            return BlobID(data: Data(repeating: UInt8(storeBlobCallCount), count: 32))
        }

        func awaitBlobFinalization(blobID: BlobID) async throws {
            finalizationCallCount += 1
            callOrder.append("finalize")
            if let error = nextFinalizationError {
                nextFinalizationError = nil
                throw error
            }
        }

        func editChat(
            conversationID: ConversationID,
            title: String?,
            pictureBlobID: BlobID?
        ) async throws -> Conversation {
            editCalls.append((title, pictureBlobID))
            callOrder.append("edit")
            if let error = nextEditError {
                nextEditError = nil
                throw error
            }
            return Conversation(
                id: conversationID,
                members: [],
                lastMessage: nil,
                lastActivity: Date(),
                type: .group,
                title: title
            )
        }
    }

    private let conversationID = ConversationID.test(7)

    private func swatch() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    // MARK: - Title validation (contract: 1...64) -

    @Test("An empty title is not submittable")
    func emptyTitleIsRejected() {
        let model = EditGroupModel(title: "")

        #expect(model.validatedTitle == nil)
    }

    @Test("A whitespace-only title is not submittable")
    func whitespaceTitleIsRejected() {
        let model = EditGroupModel(title: "   ")

        #expect(model.validatedTitle == nil)
    }

    @Test("A single character clears the contract's minimum")
    func oneCharacterIsAccepted() {
        let model = EditGroupModel(title: "a")

        #expect(model.validatedTitle == "a")
    }

    @Test("A 64-character title sits exactly on the contract's maximum and is accepted")
    func sixtyFourCharactersIsAccepted() {
        let model = EditGroupModel(title: String(repeating: "a", count: 64))

        #expect(model.validatedTitle?.count == 64)
    }

    @Test("A 65-character title exceeds the contract's maximum and is refused before sending")
    func sixtyFiveCharactersIsRejected() {
        let model = EditGroupModel(title: String(repeating: "a", count: 65))

        #expect(model.validatedTitle == nil)
    }

    @Test("An over-long title is never sent to the server")
    func overLongTitleNeverReachesTheServer() async {
        let model = EditGroupModel(title: String(repeating: "a", count: 65))
        let editor = SpyEditor()

        await #expect(throws: EditGroupIncomplete.self) {
            try await model.saveTitle(for: conversationID, using: editor)
        }

        #expect(editor.editCalls.isEmpty)
    }

    // MARK: - Save gating -

    @Test("Save stays shut on a title matching the one the group already carries")
    func unchangedTitleCannotBeSaved() {
        let model = EditGroupModel(title: "BadBoys")

        #expect(model.canSaveTitle(currentTitle: "BadBoys") == false)
    }

    @Test("Save opens once the title differs from the group's")
    func changedTitleCanBeSaved() {
        let model = EditGroupModel(title: "GoodBoys")

        #expect(model.canSaveTitle(currentTitle: "BadBoys"))
    }

    @Test("Save stays shut for the picture until one is picked")
    func pictureCannotBeSavedUntilPicked() {
        let model = EditGroupModel()

        #expect(model.canSavePicture == false)

        model.select(picture: swatch())

        #expect(model.canSavePicture)
    }

    // MARK: - Partial update construction -

    @Test("A name edit sends the title and no picture, so the group's picture is left unchanged")
    func nameEditSendsNoPicture() async throws {
        let model = EditGroupModel(title: "GoodBoys")
        let editor = SpyEditor()

        _ = try await model.saveTitle(for: conversationID, using: editor)

        #expect(editor.editCalls.count == 1)
        #expect(editor.editCalls[0].title == "GoodBoys")
        #expect(editor.editCalls[0].blobID == nil)
    }

    @Test("A name edit uploads nothing")
    func nameEditTouchesNoBlob() async throws {
        let model = EditGroupModel(title: "GoodBoys")
        let editor = SpyEditor()

        _ = try await model.saveTitle(for: conversationID, using: editor)

        #expect(editor.storeBlobCallCount == 0)
        #expect(editor.finalizationCallCount == 0)
    }

    @Test("A picture edit sends the blob and no title, so the group's name is left unchanged")
    func pictureEditSendsNoTitle() async throws {
        // Seeded with the group's current title the way the screen seeds it, to prove the title is
        // omitted by construction rather than merely because the field happened to be empty.
        let model = EditGroupModel(title: "BadBoys")
        model.select(picture: swatch())
        let editor = SpyEditor()

        _ = try await model.savePicture(for: conversationID, using: editor)

        #expect(editor.editCalls.count == 1)
        #expect(editor.editCalls[0].title == nil)
        #expect(editor.editCalls[0].blobID != nil)
    }

    @Test("A picture edit finalizes the blob before sending it, never after")
    func pictureIsFinalizedBeforeTheEdit() async throws {
        let model = EditGroupModel()
        model.select(picture: swatch())
        let editor = SpyEditor()

        _ = try await model.savePicture(for: conversationID, using: editor)

        #expect(editor.callOrder == ["store", "finalize", "edit"])
    }

    @Test("A blob the server refuses is never sent as an edit")
    func refusedBlobNeverReachesTheEdit() async {
        let model = EditGroupModel()
        model.select(picture: swatch())
        let editor = SpyEditor()
        editor.nextFinalizationError = ErrorBlob.rejected(.moderation)

        await #expect(throws: ErrorBlob.self) {
            try await model.savePicture(for: conversationID, using: editor)
        }

        #expect(editor.editCalls.isEmpty)
    }

    @Test("A retry after a failed edit reuses the reservation rather than storing a second copy")
    func retryReusesTheReservedBlob() async throws {
        let model = EditGroupModel()
        model.select(picture: swatch())
        let editor = SpyEditor()
        editor.nextEditError = ErrorEditChat.unknown

        await #expect(throws: ErrorEditChat.self) {
            try await model.savePicture(for: conversationID, using: editor)
        }

        _ = try await model.savePicture(for: conversationID, using: editor)

        #expect(editor.storeBlobCallCount == 1)
        #expect(editor.editCalls.count == 2)
    }

    @Test("Picking a different picture drops the reservation, so the new bytes are what upload")
    func newPictureDropsTheReservation() async throws {
        let model = EditGroupModel()
        model.select(picture: swatch())
        let editor = SpyEditor()

        _ = try await model.savePicture(for: conversationID, using: editor)
        model.select(picture: swatch())
        _ = try await model.savePicture(for: conversationID, using: editor)

        #expect(editor.storeBlobCallCount == 2)
    }
}

@MainActor
@Suite("Group edit permission gate")
struct ConversationCanEditTests {

    private func group(viewerState: ConversationViewerState?) -> Conversation {
        Conversation(
            id: .test(7),
            members: [],
            lastMessage: nil,
            lastActivity: Date(),
            type: .group,
            title: "BadBoys",
            viewerState: viewerState
        )
    }

    @Test("A chat whose viewer state permits editing can be edited")
    func permittedViewerCanEdit() {
        #expect(group(viewerState: ConversationViewerState(canEdit: true)).canEdit)
    }

    @Test("A chat whose viewer state withholds the permission cannot be edited")
    func unpermittedViewerCannotEdit() {
        #expect(group(viewerState: ConversationViewerState(canEdit: false)).canEdit == false)
    }

    @Test("A chat with no viewer state at all cannot be edited")
    func absentViewerStateCannotEdit() {
        #expect(group(viewerState: nil).canEdit == false)
    }

    /// The gate is the server's answer and nothing else. A group the user belongs to, holds a title
    /// in, and would plausibly own still cannot be edited without the permission — which is what
    /// keeps the affordance from being inferred from membership or chat kind.
    @Test("Membership and chat kind do not confer edit rights on their own")
    func membershipDoesNotConferEditRights() {
        let joined = Conversation(
            id: .test(7),
            members: [],
            lastMessage: nil,
            lastActivity: Date(),
            type: .group,
            title: "BadBoys",
            rosterSummary: ConversationRosterSummary(memberCount: 12, version: 1),
            viewerState: ConversationViewerState(mute: nil, canEdit: false, version: 3)
        )

        #expect(joined.canEdit == false)
    }

    @Test("A DM is not editable")
    func dmCannotBeEdited() {
        let dm = Conversation(
            id: .test(8),
            members: [],
            lastMessage: nil,
            lastActivity: Date(),
            type: .tipDm
        )

        #expect(dm.canEdit == false)
    }
}
