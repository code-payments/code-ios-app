//
//  ConversationBarLeadingControlTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
@testable import Flipcash

@MainActor
@Suite("Conversation bar leading control")
struct ConversationBarLeadingControlTests {

    private func control(
        isEditing: Bool = false,
        showsSendCash: Bool = true
    ) -> ConversationBarLeadingControl {
        ConversationBarLeadingControl(isEditing: isEditing, showsSendCash: showsSendCash)
    }

    @Test("Send Cash is the round `$` beside the field")
    func cash() {
        #expect(control() == .cash)
    }

    @Test("With nothing to send, nothing stands beside the field")
    func noneWithoutCash() {
        #expect(control(showsSendCash: false) == .none)
    }

    @Test("An edit takes the slot whatever else is true", arguments: [true, false])
    func cancelWhileEditing(showsSendCash: Bool) {
        #expect(control(isEditing: true, showsSendCash: showsSendCash) == .cancelEdit)
    }
}

@MainActor
@Suite("Conversation bar bottom row")
struct ConversationBarBottomRowTests {

    private func row(
        isEditing: Bool = false,
        acceptsMedia: Bool = true,
        attachedCount: Int = 0
    ) -> ConversationBarBottomRow {
        ConversationBarBottomRow(
            isEditing: isEditing,
            acceptsMedia: acceptsMedia,
            attachedCount: attachedCount
        )
    }

    @Test("Where the chat takes media, the row holds `+` with the camera and photos")
    func plus() {
        let row = row()
        #expect(row.plusItems == [.camera, .photos])
        #expect(!row.isEmpty)
    }

    @Test("Cash is never a menu row: the `$` beside the field takes it")
    func cashLeavesTheMenu() {
        #expect(!row().plusItems.contains(.cash))
        #expect(!row(acceptsMedia: false).plusItems.contains(.cash))
    }

    @Test("With no menu rows left, `+` goes", arguments: [false, true])
    func noPlus(isFull: Bool) {
        let row = row(acceptsMedia: isFull, attachedCount: isFull ? ComposerModel.maxAttachments : 0)
        #expect(row.plusItems.isEmpty)
        #expect(row.isEmpty)
    }

    @Test("An edit hides the bottom row")
    func hiddenWhileEditing() {
        #expect(row(isEditing: true).isEmpty)
    }
}
