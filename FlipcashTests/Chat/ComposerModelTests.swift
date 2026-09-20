//
//  ComposerModelTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Composer mode")
struct ComposerModelTests {

    @Test("A fresh composer is writing a new message")
    func freshComposerIsNew() {
        let composer = ComposerModel()
        #expect(composer.mode == .new)
        #expect(composer.draft.isEmpty)
        #expect(!composer.canSubmit)
    }

    @Test("Beginning an edit loads the message's text and stashes the unsent draft")
    func beginEditingStashesDraft() {
        let composer = ComposerModel()
        composer.draft = "half-typed"
        composer.beginEditing(messageID: MessageID(value: 3), stableID: "3", currentText: "original")

        #expect(composer.mode == .editing(messageID: MessageID(value: 3), stableID: "3"))
        #expect(composer.draft == "original")
    }

    @Test("Cancelling an edit restores the stashed draft")
    func cancellingRestoresDraft() {
        let composer = ComposerModel()
        composer.draft = "half-typed"
        composer.beginEditing(messageID: MessageID(value: 3), stableID: "3", currentText: "original")
        composer.draft = "changed my mind"
        composer.endEditing()

        #expect(composer.mode == .new)
        #expect(composer.draft == "half-typed")
    }

    @Test("Submission trims whitespace and refuses an empty draft")
    func submissionTrims() {
        let composer = ComposerModel()
        composer.draft = "  hello  "
        #expect(composer.canSubmit)
        #expect(composer.submission == "hello")

        composer.draft = "   "
        #expect(!composer.canSubmit)
        #expect(composer.submission == nil)
    }

    @Test("An edit that leaves the text unchanged cannot be submitted")
    func unchangedEditCannotSubmit() {
        let composer = ComposerModel()
        composer.beginEditing(messageID: MessageID(value: 3), stableID: "3", currentText: "original")
        #expect(!composer.canSubmit)

        composer.draft = "original edited"
        #expect(composer.canSubmit)
    }

    @Test("Clearing after a send empties the draft and stays in new-message mode")
    func clearAfterSend() {
        let composer = ComposerModel()
        composer.draft = "sent"
        composer.clear()

        #expect(composer.draft.isEmpty)
        #expect(composer.mode == .new)
    }

    private var replyTarget: ComposerModel.ReplyTarget {
        ComposerModel.ReplyTarget(
            messageID: MessageID(value: 7),
            stableID: "7",
            authorName: "Ada",
            authorID: UUID(uuidString: "8B3D4E1A-0000-4000-8000-000000000007"),
            snippet: "dinner at 7?"
        )
    }

    @Test("Starting a reply keeps what is already typed")
    func beginReplying_keepsDraft() {
        let composer = ComposerModel()
        composer.draft = "half a thought"
        composer.beginReplying(to: replyTarget)
        #expect(composer.draft == "half a thought")
        #expect(composer.replyTarget == replyTarget)
    }

    @Test("A reply submits its trimmed draft")
    func replying_submitsTrimmedDraft() {
        let composer = ComposerModel()
        composer.beginReplying(to: replyTarget)
        composer.draft = "  works  "
        #expect(composer.submission == "works")
        #expect(composer.canSubmit)
    }

    @Test("An empty reply cannot be submitted")
    func replyingWithEmptyDraft_cannotSubmit() {
        let composer = ComposerModel()
        composer.beginReplying(to: replyTarget)
        composer.draft = "   "
        #expect(composer.submission == nil)
        #expect(composer.canSubmit == false)
    }

    @Test("Dismissing the reply keeps the draft and clears the target")
    func endReplying_keepsDraft() {
        let composer = ComposerModel()
        composer.beginReplying(to: replyTarget)
        composer.draft = "works"
        composer.endReplying()
        #expect(composer.replyTarget == nil)
        #expect(composer.draft == "works")
    }

    @Test("A reply is not an edit")
    func replying_isNotEditing() {
        let composer = ComposerModel()
        composer.beginReplying(to: replyTarget)
        #expect(composer.isEditing == false)
        #expect(composer.editingStableID == nil)
    }

    @Test("Starting an edit while replying drops the reply")
    func beginEditing_whileReplying_dropsReply() {
        let composer = ComposerModel()
        composer.beginReplying(to: replyTarget)
        composer.beginEditing(messageID: MessageID(value: 9), stableID: "9", currentText: "old")
        #expect(composer.replyTarget == nil)
        #expect(composer.isEditing)
        #expect(composer.draft == "old")
    }

    @Test("Clearing after a send drops the reply")
    func clear_dropsReply() {
        let composer = ComposerModel()
        composer.beginReplying(to: replyTarget)
        composer.draft = "works"
        composer.clear()
        #expect(composer.replyTarget == nil)
        #expect(composer.draft.isEmpty)
    }

    // MARK: - Draft persistence

    @Test("A new-message composer persists its own text")
    func persistableDraft_new() {
        let composer = ComposerModel()
        composer.draft = "see you at 5 "
        #expect(composer.persistableDraft.text == "see you at 5 ")
        #expect(composer.persistableDraft.replyTarget == nil)
    }

    @Test("A replying composer persists the strip alongside the text")
    func persistableDraft_replying() {
        let composer = ComposerModel()
        composer.beginReplying(to: replyTarget)
        composer.draft = "on my way"

        let draft = composer.persistableDraft
        #expect(draft.text == "on my way")
        #expect(draft.replyTarget?.stableID == replyTarget.stableID)
        #expect(draft.replyTarget?.authorName == replyTarget.authorName)
        #expect(draft.replyTarget?.snippet == replyTarget.snippet)
    }

    @Test("An edit in progress persists the draft it displaced, not the edit body")
    func persistableDraft_editing_isTheStash() {
        let composer = ComposerModel()
        composer.draft = "half a thought"
        composer.beginEditing(messageID: MessageID(value: 3), stableID: "3", currentText: "an older message")

        #expect(composer.persistableDraft.text == "half a thought")
    }

    @Test("An edit typed into further still persists only the stash")
    func persistableDraft_editing_ignoresEditedText() {
        let composer = ComposerModel()
        composer.draft = "half a thought"
        composer.beginEditing(messageID: MessageID(value: 3), stableID: "3", currentText: "an older message")
        composer.draft = "an older message, revised"

        #expect(composer.persistableDraft.text == "half a thought")
    }

    @Test("Beginning an edit while replying stashes the text the reply was carrying")
    func persistableDraft_replyThenEdit_keepsTheText() {
        let composer = ComposerModel()
        composer.beginReplying(to: replyTarget)
        composer.draft = "half a thought"
        composer.beginEditing(messageID: MessageID(value: 3), stableID: "3", currentText: "an older message")

        // The strip goes with the field — the composer is single-mode — but the words in it are the
        // user's own, and an edit must not consume them.
        #expect(composer.persistableDraft.text == "half a thought")
        #expect(composer.persistableDraft.replyTarget == nil)
    }

    @Test("Cancelling an edit that displaced a reply puts the text back without the strip")
    func persistableDraft_replyThenEditCancelled_restoresTextOnly() {
        let composer = ComposerModel()
        composer.beginReplying(to: replyTarget)
        composer.draft = "half a thought"
        composer.beginEditing(messageID: MessageID(value: 3), stableID: "3", currentText: "an older message")
        composer.endEditing()

        #expect(composer.draft == "half a thought")
        #expect(composer.mode == .new)
        #expect(composer.persistableDraft.replyTarget == nil)
    }

    @Test("An edit that displaced nothing persists nothing")
    func persistableDraft_editing_withEmptyComposer() {
        let composer = ComposerModel()
        composer.beginEditing(messageID: MessageID(value: 3), stableID: "3", currentText: "an older message")

        #expect(composer.persistableDraft.text.isEmpty)
        #expect(composer.persistableDraft.replyTarget == nil)
    }

    @Test("Restoring puts the text back verbatim")
    func restore_text() {
        let composer = ComposerModel()
        composer.restore(ChatDraft(text: "  thinking about it  ", replyTarget: nil))
        #expect(composer.draft == "  thinking about it  ")
        #expect(composer.mode == .new)
    }

    @Test("Restoring a reply target re-aims the composer")
    func restore_replyTarget() throws {
        let composer = ComposerModel()
        composer.restore(ChatDraft(text: "", replyTarget: ChatDraft.ReplyTarget(replyTarget)))

        let restored = try #require(composer.replyTarget)
        #expect(restored == replyTarget)
    }

    @Test("Restoring never overwrites something already being typed")
    func restore_doesNotClobberAnEditedComposer() {
        let composer = ComposerModel()
        composer.draft = "already typing"
        composer.restore(ChatDraft(text: "stale", replyTarget: nil))
        #expect(composer.draft == "already typing")
    }

    @Test("Restoring never interrupts an edit")
    func restore_doesNotInterruptAnEdit() {
        let composer = ComposerModel()
        composer.beginEditing(messageID: MessageID(value: 3), stableID: "3", currentText: "an older message")
        composer.restore(ChatDraft(text: "stale", replyTarget: nil))
        #expect(composer.draft == "an older message")
        #expect(composer.isEditing)
    }

    @Test("A cleared composer persists nothing")
    func persistableDraft_afterClear() {
        let composer = ComposerModel()
        composer.beginReplying(to: replyTarget)
        composer.draft = "on my way"
        composer.clear()

        #expect(composer.persistableDraft.text.isEmpty)
        #expect(composer.persistableDraft.replyTarget == nil)
    }
}
