//
//  PaymentRequestUntitledTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import SharedCore
@testable import FlipcashCore
@testable import Flipcash

/// The contract lets a split go without text, which means it has no title or description. That draws
/// as a card headed "Request", while encrypted text that can't be opened still draws as unsupported.
@MainActor
@Suite("Payment requests: a split with no text")
struct PaymentRequestUntitledTests {

    private let chat = ConversationID.test(1)
    private let creator = UUID()
    private let viewer = UUID()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let copy = PaymentRequestCopy(displayCurrency: .usd, rates: [:])

    private func request(text: GroupPaymentRequest.Text?) -> GroupPaymentRequest {
        GroupPaymentRequest(
            id: PaymentRequestID(data: Data([1])),
            creator: creator,
            createdAt: now.addingTimeInterval(-60),
            status: .open,
            closedAt: nil,
            version: 1,
            chatID: chat,
            split: .init(
                text: text,
                currency: "usd",
                endsAt: now.addingTimeInterval(86_400),
                shares: [.init(userID: creator, nativeAmount: 10, settlement: .creator), .init(userID: viewer, nativeAmount: 10)]
            )
        )
    }

    private func store(seal: ChatSeal? = nil) -> PaymentRequests {
        PaymentRequests(
            getChatPage: { _, _, _ in [] },
            getRequest: { _ in throw ErrorGetPaymentRequest.unknown },
            openingSeal: { _ in seal }
        )
    }

    @Test("A split with no text draws as a card titled Request in the transcript, the deck and the timelines")
    func untitledSplitDraws() {
        let untitled = request(text: nil)
        let store = store()
        store.ingest([untitled])

        guard case .card(let card) = store.cardState(for: untitled.id, in: chat, sentBy: creator, copy: copy, now: now) else {
            Issue.record("expected the untitled split to draw as a card"); return
        }
        #expect(card.title == "Request")
        #expect(store.deckItems(for: chat, viewer: viewer, order: PaymentRequestDeckOrder(), copy: copy, now: now).map(\.card.title) == ["Request"])
        #expect(store.timelines(in: chat)[untitled.id]?.title == "Request")
    }

    @Test("Encrypted text the held seal can't open still draws as unsupported")
    func unopenableTextUnsupported() async throws {
        let seal = try ChatSeal(
            cipher: DefaultChatCipher.shared,
            owner: KeyPair.generate()!,
            peerPublicKey: KeyPair.generate()!.publicKey,
            conversationID: ConversationID(data: Data(repeating: 0x07, count: 32)),
            selfUserID: UUID()
        )
        let sealed = request(text: .encrypted(scheme: 1, nonce: Data(repeating: 1, count: 24), ciphertext: Data([2])))
        let store = store(seal: seal)
        store.ingest([sealed])
        await store.loadSeal(for: chat)

        #expect(store.seal(for: chat) != nil)
        #expect(store.cardState(for: sealed.id, in: chat, sentBy: creator, copy: copy, now: now) == .unsupported)
        #expect(store.deckItems(for: chat, viewer: viewer, order: PaymentRequestDeckOrder(), copy: copy, now: now).isEmpty)
    }
}
