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
}
