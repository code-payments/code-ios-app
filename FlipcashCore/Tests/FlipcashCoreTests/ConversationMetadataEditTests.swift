//
//  ConversationMetadataEditTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashAPI
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

    @Test("A description change is applied, and an empty one clears it")
    func descriptionChangeApplies() {
        var store = ConversationStore()
        store.apply(.metadataRefresh(group(1)))

        store.applyDescriptionChanged("About us", in: conversationID(1))
        #expect(store.conversations[0].description == "About us")

        store.applyDescriptionChanged("", in: conversationID(1))
        #expect(store.conversations[0].description == nil)
    }

    @Test("Metadata maps the wire description, normalizing empty to nil")
    func metadataMapsDescription() {
        func conversation(_ description: String) -> Conversation {
            Conversation(Flipcash_Chat_V1_Metadata.with {
                $0.chatID = conversationID(1).proto
                $0.type = .group
                $0.description_p = description
            })
        }

        #expect(conversation("About us").description == "About us")
        #expect(conversation("").description == nil)
    }

    @Test("A description change for a chat the store doesn't hold is a no-op")
    func descriptionChangeForUnknownChatNoOps() {
        var store = ConversationStore()

        store.applyDescriptionChanged("About us", in: conversationID(1))

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

@Suite("Conversation description edit")
struct ConversationDescriptionEditTests {

    @Test("Unchanged leaves the wrapper unset; set and clear send a value")
    func wireShape() {
        #expect(ConversationDescriptionEdit.unchanged.proto == nil)
        #expect(ConversationDescriptionEdit.set("About us").proto?.value == "About us")

        let cleared = ConversationDescriptionEdit.clear.proto
        #expect(cleared != nil)
        #expect(cleared?.value == "")
    }
}
