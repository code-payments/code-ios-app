//
//  PaymentRequestCollectionUnsupportedTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

/// A collection has no UI in this build: its widget draws as unsupported, and it stays out of the
/// deck and the transcript's timelines, while a split in the same chat still draws.
@MainActor
@Suite("Group payment requests: a collection draws as unsupported")
struct PaymentRequestCollectionUnsupportedTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let chat = ConversationID.test(1)
    private let creator = UUID()
    private let viewer = UUID()
    private let copy = PaymentRequestCopy(displayCurrency: .usd, rates: [:])

    private func request(id: UInt8, split: GroupPaymentRequest.Split?, collection: GroupPaymentRequest.Collection?) -> GroupPaymentRequest {
        GroupPaymentRequest(
            id: PaymentRequestID(data: Data([id])),
            creator: creator,
            createdAt: now.addingTimeInterval(-60),
            status: .open,
            closedAt: nil,
            version: 1,
            chatID: chat,
            split: split,
            collection: collection
        )
    }

    private var collection: GroupPaymentRequest {
        request(id: 1, split: nil, collection: .init(
            text: .plaintext(title: "Gift", description: ""),
            currency: "usd",
            endsAt: nil,
            paymentAmount: .fixed(.init(nativeAmount: 5))
        ))
    }

    private var split: GroupPaymentRequest {
        request(id: 2, split: .init(
            text: .plaintext(title: "Dinner", description: ""),
            currency: "usd",
            endsAt: now.addingTimeInterval(86_400),
            shares: [.init(userID: creator, nativeAmount: 10, settlement: .creator), .init(userID: viewer, nativeAmount: 10)]
        ), collection: nil)
    }

    private func store(holding requests: [GroupPaymentRequest]) -> PaymentRequests {
        let store = PaymentRequests(getChatPage: { _, _, _ in [] }, getRequest: { _ in throw ErrorGetPaymentRequest.unknown })
        store.ingest(requests)
        return store
    }

    @Test("A collection's widget is unsupported; a split's is a card")
    func cardState() {
        let store = store(holding: [collection, split])

        #expect(store.cardState(for: collection.id, in: chat, sentBy: creator, copy: copy, now: now) == .unsupported)
        guard case .card = store.cardState(for: split.id, in: chat, sentBy: creator, copy: copy, now: now) else {
            Issue.record("expected the split to draw as a card"); return
        }
    }

    @Test("An open collection is not in the deck or the timelines")
    func deckAndTimelines() {
        let store = store(holding: [collection, split])

        #expect(store.deck(for: chat, viewer: viewer, at: now).map(\.id) == [split.id])
        #expect(store.deckItems(for: chat, viewer: viewer, order: PaymentRequestDeckOrder(), copy: copy, now: now).map(\.request.id) == [split.id])
        #expect(Set(store.timelines(in: chat).keys) == [split.id])
    }
}
