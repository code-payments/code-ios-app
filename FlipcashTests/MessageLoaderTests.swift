//
//  MessageLoaderTests.swift
//  FlipcashTests
//

import Testing
import Foundation
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("MessageLoader windowed DB reads")
struct MessageLoaderTests {

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
        ConversationMessage(id: MessageID(value: id), senderID: nil, content: .text("m\(id)"), date: Date(timeIntervalSince1970: TimeInterval(id)), unreadSeq: id)
    }

    @Test("the initial window shows the newest page read from the DB")
    func initialWindow() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let id = ConversationID.test(1)
        try database.upsertConversationMessages((1...200).map { message(UInt64($0)) }, conversationID: id)

        let loader = MessageLoader(conversationID: id, controller: makeController(database))
        let shown = loader.messages
        #expect(shown.count == 60)              // the initial window, not the whole 200
        #expect(shown.first?.id.value == 141)   // newest 60 (141...200), oldest-first
        #expect(shown.last?.id.value == 200)
    }

    @Test("loadOlder grows the window over persisted history without a server fetch")
    func loadOlderGrowsWindow() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let id = ConversationID.test(1)
        try database.upsertConversationMessages((1...200).map { message(UInt64($0)) }, conversationID: id)
        let loader = MessageLoader(conversationID: id, controller: makeController(database))

        loader.loadOlder()                      // 60 -> 100
        #expect(loader.messages.count == 100)
        #expect(loader.messages.first?.id.value == 101)
        loader.loadOlder()                      // 100 -> 140
        #expect(loader.messages.count == 140)
        #expect(loader.messages.first?.id.value == 61)
    }

    @Test("a thread shorter than the window shows all of it")
    func shortThread() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let id = ConversationID.test(1)
        try database.upsertConversationMessages((1...10).map { message(UInt64($0)) }, conversationID: id)

        let loader = MessageLoader(conversationID: id, controller: makeController(database))
        #expect(loader.messages.map(\.id.value) == Array(1...10).map(UInt64.init))
    }
}
