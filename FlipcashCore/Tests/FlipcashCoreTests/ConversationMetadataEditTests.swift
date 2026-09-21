//
//  ConversationMetadataEditTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import FlipcashCore

/// `Chat.EditChat`'s title/picture updates: unlike the roster summary and viewer state, these
/// arrive with no version to compare, so the store applies them as received.
@Suite("Conversation metadata edits (title, picture)")
struct ConversationMetadataEditTests {

    private func conversationID(_ byte: UInt8) -> ConversationID {
        ConversationID(data: Data(repeating: byte, count: 32))
    }

    private func group(_ byte: UInt8, title: String? = nil) -> Conversation {
        Conversation(
            id: conversationID(byte),
            members: [],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0),
            type: .group,
            title: title
        )
    }

    private func picture(_ byte: UInt8) -> ProfilePicture {
        ProfilePicture(blobID: BlobID(data: Data(repeating: byte, count: 16)), thumbnailBlobID: BlobID(data: Data(repeating: byte, count: 16)))
    }

    @Test("A title change is applied to the matching chat")
    func titleChangeApplies() {
        var store = ConversationStore()
        store.apply(.metadataRefresh(group(1, title: "Old title")))

        store.applyTitleChanged("New title", in: conversationID(1))

        #expect(store.conversations[0].title == "New title")
    }

    @Test("A title change for a chat the store doesn't hold is a no-op")
    func titleChangeForUnknownChatNoOps() {
        var store = ConversationStore()

        store.applyTitleChanged("New title", in: conversationID(1))

        #expect(store.conversations.isEmpty)
    }

    @Test("A picture change is applied to the matching chat")
    func pictureChangeApplies() {
        var store = ConversationStore()
        store.apply(.metadataRefresh(group(1)))

        let newPicture = picture(0x02)
        store.applyPictureChanged(newPicture, in: conversationID(1))

        #expect(store.conversations[0].picture == newPicture)
    }

    @Test("A picture change for a chat the store doesn't hold is a no-op")
    func pictureChangeForUnknownChatNoOps() {
        var store = ConversationStore()

        store.applyPictureChanged(picture(0x02), in: conversationID(1))

        #expect(store.conversations.isEmpty)
    }
}
