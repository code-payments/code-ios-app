//
//  ConversationReceiptWiringTests.swift
//  FlipcashTests
//

import Testing
import Foundation
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Conversation receipt wiring")
struct ConversationReceiptWiringTests {

    private func waitUntil(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        for _ in 0..<50 where !condition() {
            try? await Task.sleep(for: .milliseconds(20))
        }
        try #require(condition(), "Timed out waiting for condition after ~1s", sourceLocation: sourceLocation)
    }

    private func makeController(
        _ mock: MockConversations,
        selfUserID: UserID,
        receipts: ConversationReceiptReporter,
        database: Database
    ) -> ConversationController {
        ConversationController(
            fetching: mock, messaging: mock, streaming: mock,
            contactNaming: MockDMContactNaming(),
            database: database,
            owner: .generate()!, selfUserID: selfUserID,
            receipts: receipts
        )
    }

    private func tipConversation(_ id: ConversationID, me: UserID, readPointer: MessageID?) -> Conversation {
        Conversation(
            id: id,
            members: [
                ConversationMember(userID: me, displayName: "", readPointer: readPointer),
                ConversationMember(userID: UUID(), displayName: "Alice"),
            ],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0),
            type: .tipDm
        )
    }

    private func inboundTip(id: UInt64, from sender: UserID) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id),
            senderID: sender,
            content: .cash(ExchangedFiat(
                onChainAmount: TokenAmount(quarks: 5_000_000, mint: .usdf),
                nativeAmount: FiatAmount(value: 5, currency: .usd),
                currencyRate: Rate(fx: 1, currency: .usd)
            )),
            cashAction: .tipped,
            date: Date(timeIntervalSince1970: TimeInterval(id)),
            unreadSeq: id,
            eventSequence: id
        )
    }

    @Test("a live inbound tip is counted once, and a redelivery is not counted again")
    func liveDeliveryCountsOnce() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let me = UUID(), them = UUID()
        let spy = ReceiptSpy()
        let mock = MockConversations()
        let controller = makeController(mock, selfUserID: me, receipts: spy.makeReporter(selfUserID: me), database: database)

        controller.start()
        try await waitUntil { mock.streamOpened }

        mock.emit(.newMessages(conversationID: ConversationID.test(1), messages: [inboundTip(id: 5, from: them)]))
        try await waitUntil { spy.count(of: .tips) == 1 }

        // The same message delivered again (a reconnect replay) must not re-credit.
        mock.emit(.newMessages(conversationID: ConversationID.test(1), messages: [inboundTip(id: 5, from: them)]))
        try await Task.sleep(for: .milliseconds(100))

        #expect(spy.count(of: .tips) == 1)
        #expect(spy.count(of: .messages) == 1)
        #expect(spy.amount(for: .tipsValue) == 5)
        controller.stop()
    }

    @Test("a cold catch-up seeds the local store without counting anything")
    func coldCatchUpDoesNotCount() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let me = UUID(), them = UUID()
        let spy = ReceiptSpy()
        let mock = MockConversations()
        mock.feed = [tipConversation(.test(1), me: me, readPointer: nil)]
        mock.deltaBatches = [
            .init(messages: [inboundTip(id: 1, from: them), inboundTip(id: 2, from: them)], checkpoint: 2),
        ]
        mock.deltaHead = 2
        let controller = makeController(mock, selfUserID: me, receipts: spy.makeReporter(selfUserID: me), database: database)

        controller.start()
        try await waitUntil { !controller.conversations.isEmpty }

        await controller.catchUp(conversationID: ConversationID.test(1))

        #expect(controller.messages(for: ConversationID.test(1)).map(\.id.value) == [1, 2])
        #expect(spy.counters.isEmpty)
        controller.stop()
    }

    @Test("marking read emits one received event per crossed inbound message")
    func markReadEmitsCrossedEvents() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let me = UUID(), them = UUID()
        let spy = ReceiptSpy()
        let mock = MockConversations()
        mock.feed = [tipConversation(.test(1), me: me, readPointer: MessageID(value: 1))]
        let controller = makeController(mock, selfUserID: me, receipts: spy.makeReporter(selfUserID: me), database: database)

        controller.start()
        try await waitUntil { mock.streamOpened && !controller.conversations.isEmpty }

        mock.emit(.newMessages(conversationID: ConversationID.test(1), messages: [
            inboundTip(id: 2, from: them),
            inboundTip(id: 3, from: them),
        ]))
        try await waitUntil { ((try? database.newestMessageID(conversationID: ConversationID.test(1))) ?? nil) == MessageID(value: 3) }

        await controller.markRead(conversationID: ConversationID.test(1))

        #expect(spy.tips.count == 2)
        #expect(spy.tips.allSatisfy { $0.chatType == .tipDm })
        #expect(spy.messages.isEmpty)
        controller.stop()
    }

    @Test("a second mark-read over the same window emits nothing")
    func markReadIsNotReplayed() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let me = UUID(), them = UUID()
        let spy = ReceiptSpy()
        let mock = MockConversations()
        mock.feed = [tipConversation(.test(1), me: me, readPointer: MessageID(value: 1))]
        let controller = makeController(mock, selfUserID: me, receipts: spy.makeReporter(selfUserID: me), database: database)

        controller.start()
        try await waitUntil { mock.streamOpened && !controller.conversations.isEmpty }

        mock.emit(.newMessages(conversationID: ConversationID.test(1), messages: [inboundTip(id: 2, from: them)]))
        try await waitUntil { ((try? database.newestMessageID(conversationID: ConversationID.test(1))) ?? nil) == MessageID(value: 2) }

        await controller.markRead(conversationID: ConversationID.test(1))
        await controller.markRead(conversationID: ConversationID.test(1))

        #expect(spy.tips.count == 1)
        controller.stop()
    }
}
