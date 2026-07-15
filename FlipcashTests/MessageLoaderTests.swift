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
        let loader = MessageLoader(conversationID: id, controller: makeController(database), growthInterval: .zero)

        loader.loadOlder()                      // 60 -> 100
        #expect(loader.messages.count == 100)
        #expect(loader.messages.first?.id.value == 101)
        loader.loadOlder()                      // 100 -> 140
        #expect(loader.messages.count == 140)
        #expect(loader.messages.first?.id.value == 61)
    }

    @Test("an arriving message grows the anchored window at the tail — the oldest revealed row never slides out")
    func arrivalDoesNotSlideAnchoredWindow() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let id = ConversationID.test(1)
        try database.upsertConversationMessages((1...200).map { message(UInt64($0)) }, conversationID: id)
        let loader = MessageLoader(conversationID: id, controller: makeController(database), growthInterval: .zero)

        loader.loadOlder()                      // reader pages back: window anchored at 101
        #expect(loader.messages.first?.id.value == 101)

        // A message arrives while the reader is scrolled up.
        try database.upsertConversationMessages([message(201)], conversationID: id)
        let grown = loader.messages
        #expect(grown.first?.id.value == 101)   // the revealed history is intact
        #expect(grown.last?.id.value == 201)    // the arrival grew the tail
    }

    @Test("a scroll-tick burst of loadOlder grows the window by one step, not one per tick")
    func loadOlderBurstIsDebounced() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let id = ConversationID.test(1)
        try database.upsertConversationMessages((1...200).map { message(UInt64($0)) }, conversationID: id)
        let loader = MessageLoader(conversationID: id, controller: makeController(database))   // real interval

        for _ in 0..<10 { loader.loadOlder() }   // scrollViewDidScroll fires per frame near the top
        #expect(loader.messages.count == 100)     // one +40 step accepted, nine rejected
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
