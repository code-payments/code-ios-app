//
//  ConfirmedWindowPatchTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashCore
import FlipcashStore
@testable import Flipcash

/// The cached transcript window is dropped or patched only for the chat a write touched. The
/// controller tests write rows straight to the database without reporting them: a window that
/// re-read would pick those rows up, so their absence shows the cache was kept or patched, not
/// re-read.
@MainActor
@Suite("Confirmed window patching")
struct ConfirmedWindowPatchTests {

    private let chat = ConversationID.test(1)
    private let otherChat = ConversationID.test(2)

    private func makeController(_ database: Database, server: MockConversations = MockConversations()) -> ConversationController {
        ConversationController(
            fetching: server, membership: server, viewerSettings: server, messaging: server, streaming: server,
            contactNaming: MockDMContactNaming(),
            database: database,
            owner: .generate()!, selfUserID: UUID(),
            typingHeartbeatInterval: .seconds(3), incomingTypingExpiry: .seconds(10)
        )
    }

    private func message(_ id: UInt64, _ text: String? = nil, sequence: UInt64 = 1) -> ConversationMessage {
        ConversationMessage(id: MessageID(value: id), senderID: nil, content: .text(text ?? "m\(id)"),
            date: Date(timeIntervalSince1970: TimeInterval(id)), unreadSeq: id, eventSequence: sequence)
    }

    private func seeded(_ count: UInt64 = 200) throws -> (Database, URL) {
        let (database, url) = try Database.makeTemp()
        try database.upsertConversationMessages((1...count).map { message($0) }, conversationID: chat)
        try database.upsertConversationMessages((1...count).map { message($0) }, conversationID: otherChat)
        return (database, url)
    }

    // MARK: - patchedWindow -

    @Test("patching an anchored window equals a fresh read after appends, an in-place edit and a write below the anchor")
    func anchoredPatchEqualsFreshRead() throws {
        let (database, url) = try seeded()
        defer { Database.removeTemp(at: url) }
        let window = try database.messages(conversationID: chat, from: 141)

        let written = [message(150, "edited", sequence: 2), message(201), message(202), message(10, "old edit", sequence: 2)]
        try database.upsertConversationMessages(written, conversationID: chat)
        let ids = written.map(\.id)
        let patched = ConversationController.patchedWindow(
            window, written: ids, rows: try database.messages(conversationID: chat, ids: ids), from: 141
        )

        #expect(patched == (try database.messages(conversationID: chat, from: 141)))
        #expect(patched.first?.id.value == 141)
        #expect(patched.last?.id.value == 202)
    }

    @Test("patching the newest-N window equals a fresh read: arrivals push the oldest rows out")
    func newestWindowPatchEqualsFreshRead() throws {
        let (database, url) = try seeded()
        defer { Database.removeTemp(at: url) }
        let window = try database.messagesWindow(conversationID: chat, limit: 60)

        let written = [message(201), message(202), message(203)]
        try database.upsertConversationMessages(written, conversationID: chat)
        let ids = written.map(\.id)
        let floor = try database.newestWindowFloor(conversationID: chat, limit: 60)
        let patched = ConversationController.patchedWindow(
            window, written: ids, rows: try database.messages(conversationID: chat, ids: ids), from: floor
        )

        #expect(floor == 144)
        #expect(patched == (try database.messagesWindow(conversationID: chat, limit: 60)))
    }

    @Test("a written row with no stored copy is dropped from the window, not kept stale")
    func writtenRowWithoutStoredCopyIsDropped() {
        let window = [message(1), message(2), message(3)]
        let patched = ConversationController.patchedWindow(window, written: [MessageID(value: 2)], rows: [], from: nil)
        #expect(patched.map(\.id.value) == [1, 3])
    }

    // MARK: - Controller -

    @Test("a write reported for another chat keeps the open chat's cached window")
    func writeInAnotherChatKeepsWindow() throws {
        let (database, url) = try seeded()
        defer { Database.removeTemp(at: url) }
        let controller = makeController(database)
        let before = controller.windowedMessages(for: chat, limit: 60)

        try database.upsertConversationMessages([message(201)], conversationID: chat)   // unreported
        controller.persistChanges(operation: "apply-chat-events", scope: .messages([MessageID(value: 201)], in: otherChat)) {
            try database.persistMessages([message(201)], cursor: 0, conversationID: otherChat)
        }

        #expect(controller.windowedMessages(for: chat, limit: 60) == before)
    }

    @Test("an arrival in the open chat patches in only the reported row")
    func arrivalInOpenChatPatchesReportedRow() throws {
        let (database, url) = try seeded()
        defer { Database.removeTemp(at: url) }
        let controller = makeController(database)
        _ = controller.windowedMessages(for: chat, startingAt: 101, limit: 60)

        try database.upsertConversationMessages([message(150, "unreported edit", sequence: 2)], conversationID: chat)
        controller.persistChanges(operation: "apply-chat-events", scope: .messages([MessageID(value: 201)], in: chat)) {
            try database.persistMessages([message(201)], cursor: 0, conversationID: chat)
        }

        let window = controller.windowedMessages(for: chat, startingAt: 101, limit: 60)
        #expect(window.map(\.id.value) == Array(101...201))
        #expect(window.first { $0.id.value == 150 }?.content == .text("m150"))   // not re-read
    }

    @Test("an arrival in the open chat's newest-N window matches a fresh read")
    func arrivalInNewestWindowMatchesFreshRead() throws {
        let (database, url) = try seeded()
        defer { Database.removeTemp(at: url) }
        let controller = makeController(database)
        _ = controller.windowedMessages(for: chat, limit: 60)

        controller.persistChanges(operation: "apply-chat-events", scope: .messages([MessageID(value: 201)], in: chat)) {
            try database.persistMessages([message(201)], cursor: 0, conversationID: chat)
        }

        #expect(controller.windowedMessages(for: chat, limit: 60) == (try database.messagesWindow(conversationID: chat, limit: 60)))
    }

    @Test("a persisted reaction patches the reacted row into the cached window")
    func reactionPatchesRow() throws {
        let (database, url) = try seeded()
        defer { Database.removeTemp(at: url) }
        let controller = makeController(database)
        _ = controller.windowedMessages(for: chat, limit: 60)
        let target = MessageID(value: 190)

        try database.updateReactions(messageID: target, conversationID: chat) {
            $0.applyUpdate(emoji: "🔥", actorIsSelf: false, added: true, count: 1, version: 1, reactedAt: nil)
        }
        controller.reactions.didPersist(chat, [target])

        let window = controller.windowedMessages(for: chat, limit: 60)
        #expect(window == (try database.messagesWindow(conversationID: chat, limit: 60)))
        #expect(window.first { $0.id == target }?.reactionState != nil)
    }

    @Test("a write that can drop rows in the open chat re-reads its window")
    func conversationScopeReReads() throws {
        let (database, url) = try seeded()
        defer { Database.removeTemp(at: url) }
        let controller = makeController(database)
        _ = controller.windowedMessages(for: chat, limit: 60)

        try database.upsertConversationMessages([message(201)], conversationID: chat)   // unreported
        controller.noteMessageWrite(.conversation(chat))

        #expect(controller.windowedMessages(for: chat, limit: 60).last?.id.value == 201)
    }

    @Test("a multi-batch catch-up reports its writes once, when it ends")
    func catchUpReportsOnce() async throws {
        let (database, url) = try seeded()
        defer { Database.removeTemp(at: url) }
        let server = MockConversations()
        server.deltaBatches = [
            MockConversations.DeltaBatch(messages: [message(201, sequence: 201)], checkpoint: 201),
            MockConversations.DeltaBatch(messages: [message(202, sequence: 202)], checkpoint: 202),
            MockConversations.DeltaBatch(messages: [message(203, sequence: 203)], checkpoint: 203),
        ]
        server.deltaHead = 203
        let controller = makeController(database, server: server)
        _ = controller.windowedMessages(for: chat, limit: 60)
        let revision = controller.messageRevision

        await controller.catchUp(conversationID: chat)

        #expect(controller.messageRevision == revision + 1)
        #expect(controller.windowedMessages(for: chat, limit: 60) == (try database.messagesWindow(conversationID: chat, limit: 60)))
        #expect(controller.windowedMessages(for: chat, limit: 60).last?.id.value == 203)
    }
}
