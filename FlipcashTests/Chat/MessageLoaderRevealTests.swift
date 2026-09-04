//
//  MessageLoaderRevealTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Revealing a quoted message")
struct MessageLoaderRevealTests {

    /// The same construction `MessageLoaderTests` uses — four mocks over a real temp database.
    private func makeController(_ database: Database) -> ConversationController {
        ConversationController(
            fetching: MockConversations(), messaging: MockConversations(), streaming: MockConversations(),
            contactNaming: MockDMContactNaming(),
            database: database,
            owner: .generate()!, selfUserID: UUID(),
            typingHeartbeatInterval: .seconds(3), incomingTypingExpiry: .seconds(10)
        )
    }

    private func message(_ id: UInt64) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id), senderID: nil, content: .text("m\(id)"),
            date: Date(timeIntervalSince1970: TimeInterval(id)), unreadSeq: id
        )
    }

    private func makeLoader(messageCount: Int) throws -> (loader: MessageLoader, url: URL) {
        let (database, url) = try Database.makeTemp()
        let id = ConversationID.test(1)
        try database.upsertConversationMessages((1...messageCount).map { message(UInt64($0)) }, conversationID: id)
        return (MessageLoader(conversationID: id, controller: makeController(database)), url)
    }

    @Test("A message already in the window needs no anchor move")
    func revealWindowed_keepsAnchor() throws {
        let (loader, url) = try makeLoader(messageCount: 10)
        defer { Database.removeTemp(at: url) }
        let target = try #require(loader.messages.first?.id)

        #expect(loader.reveal(target))
        #expect(loader.messages.contains { $0.id == target })
    }

    @Test("A message above the window is brought into it")
    func revealOlderMessage_movesAnchor() throws {
        let (loader, url) = try makeLoader(messageCount: 200)
        defer { Database.removeTemp(at: url) }
        // The initial window is the newest 60 (141...200), so 3 is well above it.
        let target = MessageID(value: 3)
        #expect(loader.messages.contains { $0.id == target } == false)

        #expect(loader.reveal(target))
        #expect(loader.messages.contains { $0.id == target })
    }

    @Test("A message the database has never seen cannot be revealed")
    func revealUnknownMessage_fails() throws {
        let (loader, url) = try makeLoader(messageCount: 10)
        defer { Database.removeTemp(at: url) }
        #expect(loader.reveal(MessageID(value: 9_999)) == false)
    }
}
