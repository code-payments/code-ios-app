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
}
