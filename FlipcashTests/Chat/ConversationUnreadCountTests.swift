//
//  ConversationUnreadCountTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashCore
import FlipcashStore
@testable import Flipcash

/// A row's unread count through the controller: read from the stored READ-watermark message, or,
/// when the device doesn't store it, from that one message fetched by id.
@MainActor
@Suite("ConversationController unread count")
struct ConversationUnreadCountTests {

    private let me = UUID()
    private let them = UUID()

    private func makeController(_ mock: MockConversations, database: Database) -> ConversationController {
        ConversationController(
            fetching: mock, membership: mock, viewerSettings: mock, messaging: mock, streaming: mock,
            contactNaming: MockDMContactNaming(),
            database: database,
            owner: .generate()!, selfUserID: me
        )
    }

    private func message(_ id: UInt64, seq: UInt64) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id), senderID: them, content: .text("m\(id)"),
            date: Date(timeIntervalSince1970: TimeInterval(id)), unreadSeq: seq
        )
    }

    /// A DM whose newest message is 20 (stamp 12), with the viewer's READ watermark at message 8.
    private func unreadDM() -> Conversation {
        Conversation(
            id: .test(1),
            members: [
                ConversationMember(userID: me, displayName: "me", readPointer: MessageID(value: 8)),
                ConversationMember(userID: them, displayName: "them"),
            ],
            lastMessage: message(20, seq: 12),
            lastActivity: Date(timeIntervalSince1970: 20)
        )
    }

    @Test("A stored watermark message gives the count without a fetch")
    func storedWatermarkNeedsNoFetch() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let mock = MockConversations()
        let controller = makeController(mock, database: database)
        let conversation = unreadDM()
        try database.upsertConversation(conversation)
        try database.upsertConversationMessages([message(8, seq: 5)], conversationID: conversation.id)

        await controller.resolveUnreadCount(for: conversation)

        #expect(controller.unreadCount(for: conversation) == 7)
        #expect(mock.singleMessageQueries.isEmpty)
    }

    @Test("An unstored watermark message is fetched by id, then counted")
    func unstoredWatermarkIsFetched() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let mock = MockConversations()
        mock.singleMessages = [MessageID(value: 8): message(8, seq: 5)]
        let controller = makeController(mock, database: database)
        let conversation = unreadDM()
        #expect(controller.unreadCount(for: conversation) == nil)

        await controller.resolveUnreadCount(for: conversation)
        await controller.resolveUnreadCount(for: conversation)

        #expect(controller.unreadCount(for: conversation) == 7)
        #expect(mock.singleMessageQueries == [MessageID(value: 8)])
    }

    @Test("A watermark the server has no message for stays unknown and isn't fetched again")
    func missingWatermarkIsNotRefetched() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let mock = MockConversations()
        let controller = makeController(mock, database: database)
        let conversation = unreadDM()

        await controller.resolveUnreadCount(for: conversation)
        await controller.resolveUnreadCount(for: conversation)

        #expect(controller.unreadCount(for: conversation) == nil)
        #expect(mock.singleMessageQueries == [MessageID(value: 8)])
    }

    @Test("A failed fetch stays unknown and tries again next time")
    func failedFetchRetries() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let mock = MockConversations()
        mock.singleMessageError = ErrorGetMessage.transportFailure
        let controller = makeController(mock, database: database)
        let conversation = unreadDM()

        await controller.resolveUnreadCount(for: conversation)
        #expect(controller.unreadCount(for: conversation) == nil)

        mock.singleMessageError = nil
        mock.singleMessages = [MessageID(value: 8): message(8, seq: 5)]
        await controller.resolveUnreadCount(for: conversation)

        #expect(controller.unreadCount(for: conversation) == 7)
        #expect(mock.singleMessageQueries == [MessageID(value: 8), MessageID(value: 8)])
    }
}
