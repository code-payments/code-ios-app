//
//  ComposerStackingTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
@testable import Flipcash

@Suite("Composer stacking")
struct ComposerStackingTests {

    @Test("A draft that fits on one line stays inline")
    func fitsInline() {
        #expect(!ConversationComposer.stacks(draft: "Hi", wasStacked: false, draftLineWidth: 20, inlineWidth: 200))
    }

    @Test("A draft wider than the inline field stacks")
    func wrapStacks() {
        #expect(ConversationComposer.stacks(draft: "Long", wasStacked: false, draftLineWidth: 201, inlineWidth: 200))
    }

    @Test("A newline stacks, however short the draft")
    func newlineStacks() {
        #expect(ConversationComposer.stacks(draft: "H\n", wasStacked: false, draftLineWidth: 10, inlineWidth: 200))
    }

    @Test("Deleting back under one line stays stacked")
    func staysStacked() {
        #expect(ConversationComposer.stacks(draft: "H", wasStacked: true, draftLineWidth: 10, inlineWidth: 200))
    }

    @Test("Clearing the draft unstacks")
    func clearUnstacks() {
        #expect(!ConversationComposer.stacks(draft: "", wasStacked: true, draftLineWidth: 0, inlineWidth: 200))
    }

    @Test("Before the field is measured, only a newline stacks")
    func unmeasured() {
        #expect(!ConversationComposer.stacks(draft: "Long", wasStacked: false, draftLineWidth: 500, inlineWidth: 0))
    }
}
