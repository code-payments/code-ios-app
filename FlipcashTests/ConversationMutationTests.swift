//
//  ConversationMutationTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Conversation message mutations")
struct ConversationMutationTests {

    /// The controller plus the two things a mutation test has to reach into: the transport it talks
    /// to, and the database it reads sequences from. Built the same way `ConversationControllerTests`
    /// builds its controller, with the database held rather than discarded.
    private struct Harness {
        let controller: ConversationController
        let messaging: MockConversations
        let database: Database
        let conversationID: ConversationID
    }

    private func makeHarness(selfUserID: UserID = UUID()) throws -> Harness {
        let mock = MockConversations()
        let database = try Database.makeTemp().database
        let controller = ConversationController(
            fetching: mock, messaging: mock, streaming: mock,
            contactNaming: MockDMContactNaming(),
            database: database,
            owner: .generate()!, selfUserID: selfUserID,
            typingHeartbeatInterval: .seconds(3),
            incomingTypingExpiry: .seconds(10)
        )
        return Harness(controller: controller, messaging: mock, database: database, conversationID: .test(1))
    }

    private func stored(_ id: UInt64, _ text: String, sender: UUID, eventSequence: UInt64) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id), senderID: sender, content: .text(text),
            date: Date(timeIntervalSince1970: TimeInterval(id)), unreadSeq: id, eventSequence: eventSequence
        )
    }

    @Test("Editing sends the message's stored event sequence as the expected one")
    func editSendsStoredSequence() async throws {
        let harness = try makeHarness()
        let conversationID = harness.conversationID
        let original = stored(1, "before", sender: harness.controller.selfUserID, eventSequence: 4)
        try harness.database.upsertConversationMessages([original], conversationID: conversationID)

        harness.messaging.editResult = MessageMutation(
            message: stored(1, "after", sender: harness.controller.selfUserID, eventSequence: 5),
            isConflict: false
        )

        let outcome = await harness.controller.edit(messageID: MessageID(value: 1), in: conversationID, to: "after")

        #expect(outcome == .applied)
        #expect(harness.messaging.edited.count == 1)
        #expect(harness.messaging.edited.first?.expectedEventSequence == 4)
        #expect(harness.messaging.edited.first?.text == "after")
    }

    @Test("A successful edit persists the server's copy")
    func editPersistsServerCopy() async throws {
        let harness = try makeHarness()
        let conversationID = harness.conversationID
        try harness.database.upsertConversationMessages(
            [stored(1, "before", sender: harness.controller.selfUserID, eventSequence: 4)],
            conversationID: conversationID
        )
        harness.messaging.editResult = MessageMutation(
            message: stored(1, "after", sender: harness.controller.selfUserID, eventSequence: 5),
            isConflict: false
        )

        _ = await harness.controller.edit(messageID: MessageID(value: 1), in: conversationID, to: "after")

        let persisted = try #require(try harness.database.message(id: MessageID(value: 1), conversationID: conversationID))
        #expect(persisted.content == .text("after"))
        #expect(persisted.eventSequence == 5)
    }

    @Test("A conflict persists the state that won and reports the conflict")
    func editConflictPersistsWinner() async throws {
        let harness = try makeHarness()
        let conversationID = harness.conversationID
        try harness.database.upsertConversationMessages(
            [stored(1, "before", sender: harness.controller.selfUserID, eventSequence: 4)],
            conversationID: conversationID
        )
        harness.messaging.editResult = MessageMutation(
            message: stored(1, "someone else won", sender: harness.controller.selfUserID, eventSequence: 6),
            isConflict: true
        )

        let outcome = await harness.controller.edit(messageID: MessageID(value: 1), in: conversationID, to: "mine")

        #expect(outcome == .conflicted)
        let persisted = try #require(try harness.database.message(id: MessageID(value: 1), conversationID: conversationID))
        #expect(persisted.content == .text("someone else won"))
        #expect(harness.controller.mutationAlert?.kind == .conflict)
    }

    @Test("A transport failure reverts the overlay and leaves the stored text alone")
    func editFailureRevertsOverlay() async throws {
        let harness = try makeHarness()
        let conversationID = harness.conversationID
        try harness.database.upsertConversationMessages(
            [stored(1, "before", sender: harness.controller.selfUserID, eventSequence: 4)],
            conversationID: conversationID
        )
        harness.messaging.editError = ErrorEditMessage.transportFailure

        let outcome = await harness.controller.edit(messageID: MessageID(value: 1), in: conversationID, to: "after")

        #expect(outcome == .failed)
        let displayed = harness.controller.windowedMessages(for: conversationID, startingAt: nil, limit: 50)
        #expect(displayed.first?.content == .text("before"))
        #expect(harness.controller.mutationAlert?.kind == .failure)
    }

    @Test("An unconfirmed message cannot be edited — there is no sequence to send")
    func editRejectsUnconfirmedMessage() async throws {
        let harness = try makeHarness()
        let conversationID = harness.conversationID
        try harness.database.upsertConversationMessages(
            [stored(1, "before", sender: harness.controller.selfUserID, eventSequence: 0)],
            conversationID: conversationID
        )

        let outcome = await harness.controller.edit(messageID: MessageID(value: 1), in: conversationID, to: "after")

        #expect(outcome == .failed)
        #expect(harness.messaging.edited.isEmpty)
    }

    @Test("Deleting sends the stored sequence and persists the tombstone")
    func deletePersistsTombstone() async throws {
        let harness = try makeHarness()
        let conversationID = harness.conversationID
        let me = harness.controller.selfUserID
        try harness.database.upsertConversationMessages(
            [stored(1, "before", sender: me, eventSequence: 4)],
            conversationID: conversationID
        )
        harness.messaging.deleteResult = MessageMutation(
            message: ConversationMessage(
                id: MessageID(value: 1), senderID: me,
                content: .deleted(.init(deletedBy: me, deletedAt: Date(timeIntervalSince1970: 10))),
                date: Date(timeIntervalSince1970: 1), unreadSeq: 1, eventSequence: 5
            ),
            isConflict: false
        )

        let outcome = await harness.controller.delete(messageID: MessageID(value: 1), in: conversationID)

        #expect(outcome == .applied)
        #expect(harness.messaging.deleted.first?.expectedEventSequence == 4)
        let persisted = try #require(try harness.database.message(id: MessageID(value: 1), conversationID: conversationID))
        #expect(persisted.isDeleted)
    }
}
