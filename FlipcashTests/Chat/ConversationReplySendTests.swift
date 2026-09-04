//
//  ConversationReplySendTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Sending a reply")
struct ConversationReplySendTests {

    /// Mirrors `ConversationControllerTests.makeController` — the same four mocks and a temp DB.
    private func makeController(_ mock: MockConversations, selfUserID: UserID = UUID()) -> ConversationController {
        ConversationController(
            fetching: mock, messaging: mock, streaming: mock,
            contactNaming: MockDMContactNaming(),
            database: try! Database.makeTemp().database,
            owner: .generate()!, selfUserID: selfUserID,
            typingHeartbeatInterval: .seconds(3), incomingTypingExpiry: .seconds(10)
        )
    }

    @Test("A reply carries the replied-to id to the service")
    func send_carriesRepliedTo() async throws {
        let mock = MockConversations()
        mock.sendResult = ConversationMessage(
            id: MessageID(value: 8), senderID: nil, content: .text("works"),
            date: Date(timeIntervalSince1970: 0), unreadSeq: 0, repliedTo: MessageID(value: 7)
        )
        let controller = makeController(mock)

        #expect(await controller.send("works", to: ConversationID.test(1), repliedTo: MessageID(value: 7)))

        let sent = try #require(mock.sent.last)
        #expect(sent.text == "works")
        #expect(sent.repliedTo == MessageID(value: 7))
    }

    @Test("A plain send carries no replied-to id")
    func send_withoutReply_carriesNothing() async throws {
        let mock = MockConversations()
        mock.sendResult = ConversationMessage(
            id: MessageID(value: 8), senderID: nil, content: .text("hi"),
            date: Date(timeIntervalSince1970: 0), unreadSeq: 0
        )
        let controller = makeController(mock)

        #expect(await controller.send("hi", to: ConversationID.test(1)))

        let sent = try #require(mock.sent.last)
        #expect(sent.repliedTo == nil)
    }

    @Test("The optimistic row quotes the original before the server confirms")
    func failedReply_keepsRepliedTo() async throws {
        // A failed send leaves the optimistic row in the transcript, which is the same row the
        // successful path shows while it is in flight — so this reads the pending copy directly.
        let me = UUID()
        let mock = MockConversations()
        mock.sendError = ErrorSendMessage.transportFailure
        let controller = makeController(mock, selfUserID: me)

        _ = await controller.send("works", to: ConversationID.test(1), repliedTo: MessageID(value: 7))

        let pending = try #require(controller.messages(for: ConversationID.test(1)).first)
        #expect(pending.status == .failed)
        #expect(pending.repliedTo == MessageID(value: 7))
    }

    @Test("Retrying a failed reply keeps the replied-to id")
    func retry_keepsRepliedTo() async throws {
        let me = UUID()
        let mock = MockConversations()
        mock.sendError = ErrorSendMessage.transportFailure
        let controller = makeController(mock, selfUserID: me)

        _ = await controller.send("works", to: ConversationID.test(1), repliedTo: MessageID(value: 7))
        let failed = try #require(controller.messages(for: ConversationID.test(1)).first)
        let clientID = try #require(failed.clientMessageID)

        mock.sendError = nil
        mock.sendResult = ConversationMessage(
            id: MessageID(value: 9), senderID: me, content: .text("works"),
            date: Date(timeIntervalSince1970: 0), unreadSeq: 0, repliedTo: MessageID(value: 7)
        )
        await controller.retry(clientMessageID: clientID, in: ConversationID.test(1))

        let sent = try #require(mock.sent.last)
        #expect(sent.repliedTo == MessageID(value: 7))
    }
}
