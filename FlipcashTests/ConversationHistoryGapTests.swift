//
//  ConversationHistoryGapTests.swift
//  FlipcashTests
//

import Testing
import Foundation
import FlipcashCore
import FlipcashStore
@testable import Flipcash

/// A newest page that does not overlap the stored rows leaves a gap between them. The rows below are
/// kept, the transcript reads only from the page up, and paging back fills the gap.
@MainActor
@Suite("Conversation history gap")
struct ConversationHistoryGapTests {

    private let id = ConversationID.test(1)

    private func makeController(_ server: MockConversations, database: Database) -> ConversationController {
        ConversationController(
            fetching: server, membership: server, viewerSettings: server, messaging: server, streaming: server,
            contactNaming: MockDMContactNaming(),
            database: database,
            owner: .generate()!, selfUserID: UUID(),
            typingHeartbeatInterval: .seconds(3), incomingTypingExpiry: .seconds(10)
        )
    }

    private func message(_ id: UInt64) -> ConversationMessage {
        ConversationMessage(id: MessageID(value: id), senderID: nil, content: .text("m\(id)"), date: Date(timeIntervalSince1970: TimeInterval(id)), unreadSeq: id, eventSequence: id)
    }

    private func messages(_ ids: ClosedRange<UInt64>) -> [ConversationMessage] {
        ids.map(message)
    }

    private func storedIDs(_ database: Database) throws -> [UInt64] {
        try database.getConversationMessages(conversationID: id).map(\.id.value).sorted()
    }

    /// Stores 1...200, then opens the chat to a server whose newest page is 301...350: 100 missed.
    private func openAfterMissing(_ database: Database) async throws -> (MockConversations, ConversationController) {
        try database.upsertConversationMessages(messages(1...200), conversationID: id)
        let server = MockConversations()
        server.messages = messages(301...350)
        server.olderHistory = messages(1...350)
        let controller = makeController(server, database: database)
        #expect(await controller.loadMessages(for: id))
        return (server, controller)
    }

    @Test("a newest page that misses the stored rows keeps them and records the gap")
    func gapKeepsRows() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }

        let (_, controller) = try await openAfterMissing(database)

        #expect(try storedIDs(database) == Array(1...200) + Array(301...350))
        #expect(try database.historyGap(conversationID: id) == HistoryGap(below: MessageID(value: 200), above: MessageID(value: 301)))
        // The transcript reads only the run above the gap.
        #expect(controller.messages(for: id).map(\.id.value) == Array(301...350))
    }

    @Test("the first window over a gap holds only the page, not stored rows from below it")
    func firstWindowStopsAtGap() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }

        let (_, controller) = try await openAfterMissing(database)
        let loader = MessageLoader(conversationID: id, controller: controller)

        // The opening window asks for 60 rows; the 10 below the gap must not stitch on.
        #expect(loader.messages.map(\.id.value) == Array(301...350))
        #expect(!loader.isEntireHistory(windowCount: loader.messages.count))
        #expect(controller.olderAnchor(for: id, before: 301, step: 40) == nil)
    }

    @Test("paging back fills the gap, then clears it, with every message stored once")
    func pagingFillsGap() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }

        let (server, controller) = try await openAfterMissing(database)

        await controller.loadOlderMessages(for: id)
        #expect(try database.historyGap(conversationID: id)?.above == MessageID(value: 251))
        await controller.loadOlderMessages(for: id)
        #expect(try database.historyGap(conversationID: id)?.above == MessageID(value: 201))
        // The next page reaches the stored rows and closes the gap.
        await controller.loadOlderMessages(for: id)

        #expect(server.olderQueries.map(\.value) == [301, 251, 201])
        #expect(try database.historyGap(conversationID: id) == nil)
        #expect(try storedIDs(database) == Array(1...350))
        // The rows below the old gap are readable again, contiguous with the page.
        #expect(controller.olderAnchor(for: id, before: 201, step: 40) == 161)
        #expect(controller.hasMoreOlderMessages(for: id))
    }

    @Test("a failed fill keeps the gap and the next page resumes it")
    func failedFillRetries() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }

        let (server, controller) = try await openAfterMissing(database)
        server.olderError = URLError(.notConnectedToInternet)

        await controller.loadOlderMessages(for: id)
        #expect(try database.historyGap(conversationID: id) == HistoryGap(below: MessageID(value: 200), above: MessageID(value: 301)))
        #expect(try storedIDs(database) == Array(1...200) + Array(301...350))

        server.olderError = nil
        await controller.loadOlderMessages(for: id)
        #expect(server.olderQueries.map(\.value) == [301, 301])
        #expect(try database.historyGap(conversationID: id)?.above == MessageID(value: 251))
    }

    @Test("a page that overlaps the stored rows records no gap and drops nothing")
    func overlapUnchanged() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        try database.upsertConversationMessages(messages(1...200), conversationID: id)
        let server = MockConversations()
        server.messages = messages(180...229)
        let controller = makeController(server, database: database)

        #expect(await controller.loadMessages(for: id))

        #expect(try database.historyGap(conversationID: id) == nil)
        #expect(try storedIDs(database) == Array(1...229))
    }

    @Test("a second miss before the gap fills drops the run between the gaps and keeps the oldest rows")
    func secondGapDropsIsland() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }

        let (server, controller) = try await openAfterMissing(database)
        server.messages = messages(501...550)
        #expect(await controller.loadMessages(for: id))

        #expect(try storedIDs(database) == Array(1...200) + Array(501...550))
        #expect(try database.historyGap(conversationID: id) == HistoryGap(below: MessageID(value: 200), above: MessageID(value: 501)))
        #expect(controller.messages(for: id).map(\.id.value) == Array(501...550))
    }

    @Test("an empty page below the gap means the rows under it are not this chat's history")
    func emptyPageBelowGapDropsOrphans() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }

        let (server, controller) = try await openAfterMissing(database)
        server.olderHistory = messages(301...350)

        await controller.loadOlderMessages(for: id)

        #expect(try database.historyGap(conversationID: id) == nil)
        #expect(try storedIDs(database) == Array(301...350))
        #expect(!controller.hasMoreOlderMessages(for: id))
    }

    @Test("a read pointer below the gap counts and places nothing from the rows under it")
    func readPointerBelowGap() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }

        let (_, controller) = try await openAfterMissing(database)

        // 1...200 have no sender, so they count as inbound; only the 50 above the gap may.
        #expect(controller.inboundMessageCount(after: MessageID(value: 100), in: id) == 50)
        #expect(try database.firstInboundMessageID(conversationID: id, after: MessageID(value: 100), excludingSender: UUID()) == 301)
    }

    @Test("revealing a stored message below the gap pages the gap closed first")
    func revealBelowGap() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }

        let (_, controller) = try await openAfterMissing(database)
        let loader = MessageLoader(conversationID: id, controller: controller)

        // Stored, but no window reaches it across the gap.
        #expect(!loader.reveal(MessageID(value: 100)))

        #expect(await loader.revealPaging(MessageID(value: 100)))
        #expect(try database.historyGap(conversationID: id) == nil)
        #expect(loader.messages.contains { $0.id.value == 100 })
        #expect(loader.messages.map(\.id.value).last == 350)
    }
}
