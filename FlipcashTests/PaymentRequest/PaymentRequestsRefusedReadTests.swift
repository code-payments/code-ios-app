//
//  PaymentRequestsRefusedReadTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
@testable import FlipcashCore
@testable import Flipcash

/// The server can refuse a request it serves a moment later, as it does for a member it doesn't list
/// yet, so a refused card must read again on its chat's next refetch rather than stay unsupported.
@MainActor
@Suite("Payment requests: a refused read retries on its chat's refetch")
struct PaymentRequestsRefusedReadTests {

    private let chat = ConversationID.test(1)
    private let otherChat = ConversationID.test(2)
    private let creator = UUID()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let copy = PaymentRequestCopy(displayCurrency: .usd, rates: [:])
    private let id = PaymentRequestID(data: Data([1]))

    /// Answers each request read with `failure`, or with the request once it is `nil`, counting reads.
    @MainActor
    private final class Server {
        var failure: ErrorGetPaymentRequest? = .denied
        var reads = 0
    }

    private func request() -> GroupPaymentRequest {
        GroupPaymentRequest(
            id: id,
            creator: creator,
            createdAt: now.addingTimeInterval(-60),
            status: .open,
            closedAt: nil,
            version: 1,
            chatID: chat,
            split: .init(
                text: .plaintext(title: "Dinner", description: ""),
                currency: "usd",
                endsAt: now.addingTimeInterval(86_400),
                shares: [.init(userID: creator, nativeAmount: 10, settlement: .creator), .init(userID: UUID(), nativeAmount: 10)]
            )
        )
    }

    private func store(_ server: Server) -> PaymentRequests {
        let request = request()
        return PaymentRequests(
            getChatPage: { _, _, _ in [] },
            getRequest: { _ in
                server.reads += 1
                if let failure = server.failure { throw failure }
                return (request, nil, nil)
            }
        )
    }

    private func state(_ store: PaymentRequests) -> PaymentRequestCardState {
        store.cardState(for: id, in: chat, sentBy: creator, copy: copy, now: now)
    }

    @Test("A refused card draws once its chat's next refetch reads it")
    func refusedThenRead() async {
        let server = Server()
        let store = store(server)

        await store.fetchIfMissing(id, in: chat)
        #expect(state(store) == .unsupported)

        server.failure = nil
        await store.refreshChat(chat)
        expectCard(store)
    }

    @Test(
        "A retry that fails keeps the card unsupported without hurrying the poll, until a read succeeds",
        arguments: [ErrorGetPaymentRequest.denied, .notFound, .transportFailure]
    )
    func failedRetryKeepsMark(failure: ErrorGetPaymentRequest) async {
        let server = Server()
        let store = store(server)
        await store.fetchIfMissing(id, in: chat)

        server.failure = failure
        await store.refreshChat(chat)
        #expect(server.reads == 2)
        #expect(state(store) == .unsupported)
        #expect(!store.isSettling(chat))

        server.failure = nil
        await store.refreshChat(chat)
        expectCard(store)
    }

    @Test("Another chat's refetch doesn't read a request refused for this one")
    func otherChatLeavesMark() async {
        let server = Server()
        let store = store(server)
        await store.fetchIfMissing(id, in: chat)

        server.failure = nil
        await store.refreshChat(otherChat)
        #expect(server.reads == 1)
        #expect(state(store) == .unsupported)
    }

    @Test("A refresh named for a chat retries there, and a later refusal naming no chat keeps that")
    func refreshNamedForChat() async {
        let server = Server()
        let store = store(server)
        _ = try? await store.refresh(id, in: chat)
        _ = try? await store.refresh(id)
        #expect(state(store) == .unsupported)

        server.failure = nil
        await store.refreshChat(chat)
        expectCard(store)
    }

    @Test("A read that fails in transit and is refused on its retry still retries on its chat")
    func transportFailureThenRefused() async {
        let server = Server()
        server.failure = .transportFailure
        let store = store(server)
        await store.fetchIfMissing(id, in: chat)

        server.failure = .denied
        await store.refreshChat(otherChat)
        #expect(state(store) == .unsupported)

        server.failure = nil
        await store.refreshChat(chat)
        expectCard(store)
    }

    @Test("Forgetting the chat drops its refused request's mark, and its refetch no longer reads it")
    func forgetDropsMark() async {
        let server = Server()
        let store = store(server)
        await store.fetchIfMissing(id, in: chat)

        store.forget(conversations: [chat])
        #expect(!store.unavailable.contains(id))

        server.failure = nil
        await store.refreshChat(chat)
        #expect(server.reads == 1)
    }

    private func expectCard(_ store: PaymentRequests, sourceLocation: SourceLocation = #_sourceLocation) {
        guard case .card = state(store) else {
            Issue.record("expected the request to draw as a card, got \(state(store))", sourceLocation: sourceLocation); return
        }
    }
}
