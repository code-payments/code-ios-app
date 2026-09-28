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
        showsSendCash: Bool = true,
        acceptsMedia: Bool = true,
        attachedCount: Int = 0
    ) -> ConversationBarLeadingControl {
        ConversationBarLeadingControl(
            isEditing: isEditing,
            chatExists: chatExists,
            showsSendCash: showsSendCash,
            acceptsMedia: acceptsMedia,
            attachedCount: attachedCount
        )
    }

    @Test("Before the chat exists, Send Cash stays the full-width call to action", arguments: [true, false])
    func callToActionBeforeChatExists(acceptsMedia: Bool) {
        #expect(control(chatExists: false, acceptsMedia: acceptsMedia) == .sendCash)
    }

    @Test("Before the chat exists with nothing to send, the slot is empty")
    func emptyBeforeChatExistsWithoutCash() {
        #expect(control(chatExists: false, showsSendCash: false) == .none)
    }

    @Test("Once the chat exists, the slot is the attach menu with every row")
    func attachMenuOnceChatExists() {
        #expect(control() == .attach([.cash, .camera, .photos]))
    }

    @Test("An E2EE chat keeps the attach menu with Cash alone")
    func attachMenuCashOnlyWithoutMedia() {
        #expect(control(acceptsMedia: false) == .attach([.cash]))
    }

    @Test("A chat that takes neither cash nor media leaves the slot empty")
    func emptyWithoutCashOrMedia() {
        #expect(control(showsSendCash: false, acceptsMedia: false) == .none)
    }

    @Test("A full composer in a chat without cash leaves the slot empty")
    func emptyWhenFullWithoutCash() {
        #expect(control(showsSendCash: false, attachedCount: ComposerModel.maxAttachments) == .none)
    }

    @Test("An edit takes the slot whatever else is true", arguments: [true, false])
    func cancelWhileEditing(chatExists: Bool) {
        #expect(control(isEditing: true, chatExists: chatExists) == .cancelEdit)
    }
}
