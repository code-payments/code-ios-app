//
//  PaymentRequestsSealTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import SharedCore
@testable import FlipcashCore
@testable import Flipcash

/// An encrypted request title waits on the chat's seal, so a failed seal read must not strand it.
@MainActor
@Suite("Payment requests: chat seal retries")
struct PaymentRequestsSealTests {

    private let chat = ConversationID.test(1)

    private static func seal() throws -> ChatSeal {
        try ChatSeal(
            cipher: DefaultChatCipher.shared,
            owner: KeyPair.generate()!,
            peerPublicKey: KeyPair.generate()!.publicKey,
            conversationID: ConversationID(data: Data(repeating: 0x07, count: 32)),
            selfUserID: UUID()
        )
    }

    /// Answers `nil` until `available` is set, counting reads.
    @MainActor
    private final class SealSource {
        var available: ChatSeal?
        var reads = 0
    }

    private func store(_ source: SealSource) -> PaymentRequests {
        PaymentRequests(
            getChatPage: { _, _, _ in [] },
            getRequest: { _ in throw ErrorGetPaymentRequest.unknown },
            openingSeal: { _ in
                source.reads += 1
                return source.available
            }
        )
    }

    @Test("A chat refresh retries a seal the last read could not open")
    func refreshChatRetriesSeal() async throws {
        let source = SealSource()
        let store = store(source)

        await store.refreshChat(chat)
        #expect(store.seal(for: chat) == nil)

        source.available = try Self.seal()
        await store.refreshChat(chat)
        #expect(store.seal(for: chat) != nil)
    }

    @Test("A held seal is not read again")
    func heldSealIsKept() async throws {
        let source = SealSource()
        source.available = try Self.seal()
        let store = store(source)

        await store.refreshChat(chat)
        await store.refreshChat(chat)
        #expect(source.reads == 1)
    }

    private func encryptedRequest() -> GroupPaymentRequest {
        GroupPaymentRequest(
            id: PaymentRequestID(data: Data([1])),
            creator: UUID(),
            createdAt: .now,
            status: .open,
            closedAt: nil,
            version: 1,
            chatID: chat,
            split: .init(
                text: .encrypted(scheme: 1, nonce: Data(repeating: 1, count: 24), ciphertext: Data([2])),
                currency: "usd",
                endsAt: .now.addingTimeInterval(3600),
                shares: []
            )
        )
    }

    @Test("Encrypted text with no seal keeps the chat settling until the seal opens")
    func settlesOnSeal() async throws {
        let source = SealSource()
        let store = store(source)
        let request = encryptedRequest()
        store.ingest([request])

        await store.refreshChat(chat)
        #expect(store.isSettling(chat))
        #expect(store.isSettling(request: request.id))

        source.available = try Self.seal()
        await store.refreshChat(chat)
        #expect(!store.isSettling(chat))
        #expect(!store.isSettling(request: request.id))
    }

    @Test("A request read that failed is read again by the next chat refresh")
    func failedReadRetried() async throws {
        var reads = 0
        var fails = true
        let request = encryptedRequest()
        let store = PaymentRequests(
            getChatPage: { _, _, _ in [] },
            getRequest: { _ in
                reads += 1
                if fails { throw ErrorGetPaymentRequest.transportFailure }
                return (request, nil)
            },
            openingSeal: { _ in try? Self.seal() }
        )

        await store.fetchIfMissing(request.id)
        #expect(store.isSettling(chat))

        fails = false
        await store.refreshChat(chat)
        #expect(reads == 2)
        #expect(store.request(request.id) != nil)
        #expect(!store.isSettling(chat))
    }

    @Test("Retries back off from 2 s and stop at the poll interval")
    func retryDelay() {
        #expect(PaymentRequests.retryDelay(attempt: 0) == .seconds(2))
        #expect(PaymentRequests.retryDelay(attempt: 1) == .seconds(4))
        #expect(PaymentRequests.retryDelay(attempt: 10) == PaymentRequests.pollInterval)
    }
}
