//
//  ConversationReactionsTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashCore
import FlipcashStore
@testable import Flipcash

@MainActor
@Suite("Conversation reactions")
struct ConversationReactionsTests {

    private let conversationID = ConversationID.test(1)
    private let messageID = MessageID(value: 1)
    private let selfUserID = UUID()

    private struct Harness {
        let reactions: ConversationReactions
        let messaging: MockConversations
        let database: Database
        let recents: RecentReactionsStore
    }

    private func makeHarness() throws -> Harness {
        let messaging = MockConversations()
        let database = try Database.makeTemp().database
        try database.upsertConversationMessages([
            ConversationMessage(
                id: messageID, senderID: UUID(), content: .text("hi"),
                date: Date(timeIntervalSince1970: 1), unreadSeq: 1, eventSequence: 1
            ),
        ], conversationID: conversationID)
        let reactions = ConversationReactions(messaging: messaging, database: database, owner: .generate()!, selfUserID: selfUserID)
        let defaults = UserDefaults(suiteName: "reactions-\(UUID())")!
        let recents = RecentReactionsStore(defaults: defaults, owner: KeyPair.generate()!.publicKey)
        reactions.recents = recents
        return Harness(reactions: reactions, messaging: messaging, database: database, recents: recents)
    }

    private func pills(_ harness: Harness) throws -> [ReactionPill] {
        let stored = try harness.database.message(id: messageID, conversationID: conversationID)
        let displayed = harness.reactions.displayed(stored.map { [$0] } ?? [], in: conversationID)
        return displayed.first?.reactionState?.pills ?? []
    }

    private func storedPills(_ harness: Harness) throws -> [ReactionPill] {
        try harness.database.message(id: messageID, conversationID: conversationID)?.reactionState?.pills ?? []
    }

    private func ok(_ emoji: String, count: UInt64, self reacted: Bool, version: UInt64) -> EmojiReaction {
        EmojiReaction(
            emoji: emoji,
            count: count,
            selfReactor: reacted ? Reactor(userID: selfUserID, reactedAt: Date(timeIntervalSince1970: 10), version: version) : nil,
            sampleReactors: [],
            version: version
        )
    }

    @Test("A tap shows pending at once, then persists the server's aggregate")
    func tapConfirms() async throws {
        let harness = try makeHarness()
        let (gate, open) = AsyncStream<Void>.makeStream()
        let answer = ok("🔥", count: 1, self: true, version: 1)
        harness.messaging.reactionHandler = { _ in
            for await _ in gate { break }
            return answer
        }

        harness.reactions.toggle("🔥", messageID: messageID, in: conversationID)

        #expect(try pills(harness) == [ReactionPill(emoji: "🔥", count: 1, selfReacted: true, pending: true)])
        #expect(try storedPills(harness).isEmpty)

        open.yield()
        try await waitUntil { try storedPills(harness) == [ReactionPill(emoji: "🔥", count: 1, selfReacted: true, pending: false)] }
        #expect(try pills(harness) == [ReactionPill(emoji: "🔥", count: 1, selfReacted: true, pending: false)])
        #expect(harness.messaging.reacted == [.init(op: .add, messageID: messageID, emoji: "🔥")])
        #expect(harness.reactions.error == nil)
    }

    @Test("Adding records the emoji in recents; removing does not")
    func addRecordsRecents() async throws {
        let harness = try makeHarness()
        harness.messaging.reactionHandler = { [selfUserID] call in
            EmojiReaction(
                emoji: call.emoji,
                count: call.op == .add ? 1 : 0,
                selfReactor: call.op == .add ? Reactor(userID: selfUserID, reactedAt: nil, version: 1) : nil,
                sampleReactors: [],
                version: call.op == .add ? 1 : 2
            )
        }

        harness.reactions.toggle("😢", messageID: messageID, in: conversationID)
        try await waitUntil { harness.messaging.reacted.count == 1 && (try? storedPills(harness))?.isEmpty == false }
        harness.reactions.toggle("😢", messageID: messageID, in: conversationID)
        try await waitUntil { harness.messaging.reacted.count == 2 && (try? storedPills(harness))?.isEmpty == true }

        #expect(harness.messaging.reacted.map(\.op) == [.add, .remove])
        #expect(harness.recents.row(limit: 1) == ["😢"])
    }

    @Test("A rejected add reverts and surfaces the user-facing error", arguments: [
        (ErrorAddReaction.tooManyReactionTypes, ReactionError.tooManyReactionTypes),
        (ErrorAddReaction.transportFailure, ReactionError.reactionFailed),
    ])
    func failureReverts(thrown: ErrorAddReaction, expected: ReactionError) async throws {
        let harness = try makeHarness()
        harness.messaging.reactionHandler = { _ in throw thrown }

        harness.reactions.toggle("🔥", messageID: messageID, in: conversationID)

        try await waitUntil(harness.reactions) { $0.error != nil }
        #expect(harness.reactions.error == expected)
        #expect(try pills(harness).isEmpty)
    }

    @Test("Thrown errors map to the failure the state settles with")
    func failureMapping() {
        #expect(ConversationReactions.failure(for: ErrorAddReaction.cannotReact) == .cannotReact)
        #expect(ConversationReactions.failure(for: ErrorRemoveReaction.messageNotFound) == .messageNotFound)
        #expect(ConversationReactions.failure(for: ErrorRemoveReaction.transportFailure) == .network)
        #expect(ConversationReactions.failure(for: CancellationError()) == .network)
    }

    @Test("Stream updates persist, attributing the user's own reactions to them")
    func streamUpdates() throws {
        let harness = try makeHarness()
        let other = UUID()

        harness.reactions.apply([
            DecodedReactionUpdate(messageID: messageID, emoji: "👍", actor: other, added: true, count: 1, version: 1, reactedAt: nil),
            DecodedReactionUpdate(messageID: messageID, emoji: "👍", actor: selfUserID, added: true, count: 2, version: 2, reactedAt: Date(timeIntervalSince1970: 5)),
            // Older than what already landed: ignored.
            DecodedReactionUpdate(messageID: messageID, emoji: "👍", actor: other, added: false, count: 1, version: 1, reactedAt: nil),
        ], in: conversationID)

        #expect(try storedPills(harness) == [ReactionPill(emoji: "👍", count: 2, selfReacted: true, pending: false)])
    }

    private func summary(_ reactions: EmojiReaction...) -> ReactionState {
        var state = ReactionState()
        state.applySummary(reactions.map(\.summaryEntry))
        return state
    }

    @Test("A refresh brings in reactions made while this account wasn't listening")
    func refreshAddsMissed() async throws {
        let harness = try makeHarness()
        harness.messaging.reactionSummaries = [messageID: summary(ok("🔥", count: 1, self: false, version: 1))]

        await harness.reactions.refresh([messageID], in: conversationID)

        #expect(harness.messaging.reactionSummaryRequests == [[messageID]])
        #expect(try storedPills(harness) == [ReactionPill(emoji: "🔥", count: 1, selfReacted: false, pending: false)])
    }

    @Test("A refresh drops an emoji that was removed while away")
    func refreshDropsRemoved() async throws {
        let harness = try makeHarness()
        harness.messaging.reactionSummaries = [messageID: summary(ok("🔥", count: 1, self: false, version: 1))]
        await harness.reactions.refresh([messageID], in: conversationID)

        harness.messaging.reactionSummaries = [messageID: summary(ok("👍", count: 1, self: false, version: 1))]
        await harness.reactions.refresh([messageID], in: conversationID)

        #expect(try storedPills(harness) == [ReactionPill(emoji: "👍", count: 1, selfReacted: false, pending: false)])
    }

    @Test("A refresh older than the stored state leaves it alone")
    func refreshIgnoresStale() async throws {
        let harness = try makeHarness()
        harness.reactions.apply([
            DecodedReactionUpdate(messageID: messageID, emoji: "🔥", actor: UUID(), added: true, count: 2, version: 2, reactedAt: nil),
        ], in: conversationID)
        harness.messaging.reactionSummaries = [messageID: summary(ok("🔥", count: 1, self: false, version: 1))]

        await harness.reactions.refresh([messageID], in: conversationID)

        #expect(try storedPills(harness) == [ReactionPill(emoji: "🔥", count: 2, selfReacted: false, pending: false)])
    }
}

@MainActor
@Suite("Recent reactions store")
struct RecentReactionsStoreTests {

    @Test("Usage survives a reload, scoped to its owner")
    func persistsPerOwner() throws {
        let defaults = UserDefaults(suiteName: "recents-\(UUID())")!
        let owner = KeyPair.generate()!.publicKey

        let store = RecentReactionsStore(defaults: defaults, owner: owner)
        store.record("🎉", at: Date(timeIntervalSince1970: 1))
        store.record("🎉", at: Date(timeIntervalSince1970: 2))
        store.record("👀", at: Date(timeIntervalSince1970: 3))

        let reloaded = RecentReactionsStore(defaults: defaults, owner: owner)
        #expect(reloaded.row(limit: RecentReactionsStore.stripLimit) == ["🎉", "👀", "❤️", "👍", "😂", "😮"])

        let other = RecentReactionsStore(defaults: defaults, owner: KeyPair.generate()!.publicKey)
        #expect(other.row(limit: RecentReactionsStore.stripLimit) == RecentReactions.defaults)
    }

    @Test("Undrawable emoji are left out of the row")
    func skipsUndrawable() {
        let store = RecentReactionsStore(defaults: UserDefaults(suiteName: "recents-\(UUID())")!, owner: KeyPair.generate()!.publicKey)
        store.record("🫩")
        #expect(store.row(limit: 2, undrawable: ["🫩"]) == ["❤️", "👍"])
    }
}
