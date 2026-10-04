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
        chatExists: Bool = true,
        showsSendCash: Bool = true
    ) -> ConversationBarLeadingControl {
        ConversationBarLeadingControl(isEditing: isEditing, chatExists: chatExists, showsSendCash: showsSendCash)
    }

    @Test("Before the chat exists, Send Cash stays the full-width call to action")
    func callToActionBeforeChatExists() {
        #expect(control(chatExists: false) == .sendCash)
    }

    @Test("Before the chat exists with nothing to send, nothing stands outside the field")
    func emptyBeforeChatExistsWithoutCash() {
        #expect(control(chatExists: false, showsSendCash: false) == .none)
    }

    @Test("Once the chat exists, Send Cash is the round `$` beside the field")
    func cashOnceChatExists() {
        #expect(control() == .cash)
    }

    @Test("Once the chat exists with nothing to send, nothing stands beside the field")
    func noneOnceChatExistsWithoutCash() {
        #expect(control(showsSendCash: false) == .none)
    }

    @Test("An edit takes the slot whatever else is true", arguments: [true, false])
    func cancelWhileEditing(chatExists: Bool) {
        #expect(control(isEditing: true, chatExists: chatExists) == .cancelEdit)
    }
}

@MainActor
@Suite("Conversation bar bottom row")
struct ConversationBarBottomRowTests {

    private func row(
        isEditing: Bool = false,
        chatExists: Bool = true,
        acceptsMedia: Bool = true,
        attachedCount: Int = 0
    ) -> ConversationBarBottomRow {
        ConversationBarBottomRow(
            isEditing: isEditing,
            chatExists: chatExists,
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

    @Test("Before the chat exists there is no bottom row")
    func hiddenBeforeChatExists() {
        #expect(row(chatExists: false).isEmpty)
    }
}
