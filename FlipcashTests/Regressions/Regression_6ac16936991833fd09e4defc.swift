//
//  Regression_6ac16936991833fd09e4defc.swift
//  FlipcashTests
//
//  "Failed to persist message reactions [apply-reaction-updates]" — database is locked (code: 5).
//  updateReactions read the message row before writing it inside a DEFERRED transaction. While
//  another connection (the notification extension's per-push writer) held the write lock, the
//  snapshot upgrade returned SQLITE_BUSY at once, bypassing the busy handler. mergeReactions and
//  upsertConversationMessages had the same read-then-write shape.
//
//  Fix: those transactions take the write lock up front with BEGIN IMMEDIATE.
//

import Foundation
import Testing
import FlipcashCore
import FlipcashStore
@testable import Flipcash

@MainActor
@Suite("Regression: 6ac1693 – reaction writes fail SQLITE_BUSY against a rival writer", .bug("6ac16936991833fd09e4defc"))
struct Regression_6ac1693 {

    private let conversationID = ConversationID.test(1)
    private let messageID = MessageID(value: 1)
    private let selfUserID = UUID()

    private func message(_ text: String = "hi", eventSequence: UInt64 = 1) -> ConversationMessage {
        ConversationMessage(
            id: messageID, senderID: UUID(), content: .text(text),
            date: Date(timeIntervalSince1970: 1), unreadSeq: 1, eventSequence: eventSequence
        )
    }

    /// Takes the write lock on a second `Database` over the same file, the way the extension's
    /// connection does, and commits it shortly after on another thread.
    private func holdWriteLock(url: URL) throws -> Task<Void, Error> {
        let rival = try Database(url: url)
        try rival.write { try $0.run("BEGIN IMMEDIATE TRANSACTION") }
        return Task.detached {
            try await Task.delay(milliseconds: 500)
            try rival.write { try $0.run("COMMIT TRANSACTION") }
        }
    }

    @Test("a streamed reaction update waits for a rival writer instead of failing the snapshot upgrade")
    func applyReactionUpdates_rivalWriterHoldsLock_waitsThenPersists() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        try database.upsertConversationMessages([message()], conversationID: conversationID)
        let reactions = ConversationReactions(messaging: MockConversations(), database: database, owner: .generate()!, selfUserID: selfUserID)

        let release = try holdWriteLock(url: url)
        reactions.apply([
            DecodedReactionUpdate(messageID: messageID, emoji: "👍", actor: UUID(), added: true, count: 1, version: 1, reactedAt: nil),
        ], in: conversationID)
        try await release.value

        let pills = try database.message(id: messageID, conversationID: conversationID)?.reactionState?.pills ?? []
        #expect(pills == [ReactionPill(emoji: "👍", count: 1, selfReacted: false, pending: false)])
    }

    @Test("a reaction summary refresh waits for a rival writer instead of failing the snapshot upgrade")
    func mergeReactions_rivalWriterHoldsLock_waitsThenPersists() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        try database.upsertConversationMessages([message()], conversationID: conversationID)
        var summary = ReactionState()
        summary.applyUpdate(emoji: "👍", actorIsSelf: false, added: true, count: 1, version: 1, reactedAt: nil)

        let release = try holdWriteLock(url: url)
        let changed = try database.mergeReactions([messageID: summary], conversationID: conversationID)
        try await release.value

        #expect(changed == 1)
    }

    @Test("storing a newer copy of a known message waits for a rival writer instead of failing the snapshot upgrade")
    func upsertConversationMessages_rivalWriterHoldsLock_waitsThenPersists() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        try database.upsertConversationMessages([message()], conversationID: conversationID)

        let release = try holdWriteLock(url: url)
        // A newer event sequence, so the stored row is read and then overwritten.
        try database.upsertConversationMessages([message("edited", eventSequence: 2)], conversationID: conversationID)
        try await release.value

        #expect(try database.message(id: messageID, conversationID: conversationID)?.content == .text("edited"))
    }
}
