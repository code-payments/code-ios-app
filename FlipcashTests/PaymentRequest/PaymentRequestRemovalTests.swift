//
//  PaymentRequestRemovalTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
@testable import FlipcashCore
import FlipcashStore
@testable import Flipcash

private let leaving = ConversationID.test(1)
private let staying = ConversationID.test(2)
private let leavingRequest = PaymentRequestID(data: Data([1]))
private let stayingRequest = PaymentRequestID(data: Data([2]))
private let owner = UUID()

private func conversation(_ id: ConversationID, type: ConversationType) -> Conversation {
    Conversation(id: id, members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 100), type: type, creator: owner)
}

private func request(_ id: PaymentRequestID, in chat: ConversationID) -> GroupPaymentRequest {
    GroupPaymentRequest(
        id: id, creator: owner, createdAt: nil, status: .open, closedAt: nil, version: 1, chatID: chat,
        split: .init(text: .plaintext(title: "Dinner", description: ""), currency: "usd", endsAt: nil, shares: [])
    )
}

/// A database holding one request in each of two conversations of `type`.
private func seeded(type: ConversationType) throws -> Database {
    let database = Database.mock
    try database.upsertConversation(conversation(leaving, type: type))
    try database.upsertConversation(conversation(staying, type: type))
    try database.upsertPaymentRequests([request(leavingRequest, in: leaving), request(stayingRequest, in: staying)])
    return database
}

private func expectOnlyStayingRemains(_ database: Database) throws {
    #expect(try database.paymentRequests(in: leaving).isEmpty)
    #expect(try database.paymentRequest(id: leavingRequest) == nil)
    #expect(try database.paymentRequests(in: staying).map(\.id) == [stayingRequest])
}

@Suite("Payment requests leave with their conversation")
struct DatabasePaymentRequestRemovalTests {

    @Test("Leaving a conversation deletes its payment requests")
    func deleteConversation() throws {
        let database = try seeded(type: .group)
        try database.deleteConversation(conversationID: leaving)
        try expectOnlyStayingRemains(database)
    }

    @Test("A group feed that reports a group departed deletes its payment requests")
    func departedGroup() throws {
        let database = try seeded(type: .group)
        try database.replaceGroupFeed([conversation(staying, type: .group)], departed: [leaving])
        try expectOnlyStayingRemains(database)
    }

    @Test("A feed that drops a conversation deletes its payment requests")
    func droppedFromFeed() throws {
        let database = try seeded(type: .contactDm)
        try database.replaceConversationFeed([conversation(staying, type: .contactDm)], type: .contactDm)
        try expectOnlyStayingRemains(database)
    }

    @Test("A group feed that keeps the group keeps its payment requests")
    func keptGroup() throws {
        let database = try seeded(type: .group)
        try database.replaceGroupFeed([conversation(leaving, type: .group), conversation(staying, type: .group)], departed: [])
        #expect(try database.paymentRequests(in: leaving).map(\.id) == [leavingRequest])
        #expect(try database.paymentRequests(in: staying).map(\.id) == [stayingRequest])
    }
}

@MainActor
@Suite("Held payment requests of a departed chat")
struct PaymentRequestsForgetTests {

    @Test("Forgetting a chat drops its held requests and keeps the others")
    func forgets() {
        let store = PaymentRequests(
            getChatPage: { _, _, _ in throw ErrorGetChatPaymentRequests.unknown },
            getRequest: { _ in throw ErrorGetPaymentRequest.unknown },
            database: Database.mock
        )
        store.ingest([request(leavingRequest, in: leaving), request(stayingRequest, in: staying)])
        store.forget(conversations: [leaving])
        #expect(store.request(leavingRequest) == nil)
        #expect(store.request(stayingRequest) != nil)
    }
}
