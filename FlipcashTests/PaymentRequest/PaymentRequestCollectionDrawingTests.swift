//
//  PaymentRequestCollectionDrawingTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

/// With the Group Money UI off, a collection draws as unsupported and stays out of the deck and the
/// transcript's timelines. With it on, a collection draws as its card and taps through from its
/// payment rows, and no request is in the deck.
@MainActor
@Suite("Group payment requests: drawing a collection")
struct PaymentRequestCollectionDrawingTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let chat = ConversationID.test(1)
    private let creator = UUID()
    private let viewer = UUID()
    private let copy = PaymentRequestCopy(displayCurrency: .usd, rates: [:])

    private func request(id: UInt8, split: GroupPaymentRequest.Split?, collection: GroupPaymentRequest.Collection?, status: GroupPaymentRequest.Status = .open, paid: Double = 0) -> GroupPaymentRequest {
        GroupPaymentRequest(
            id: PaymentRequestID(data: Data([id])),
            creator: creator,
            createdAt: now.addingTimeInterval(-60),
            status: status,
            closedAt: nil,
            version: 1,
            chatID: chat,
            split: split,
            collection: collection,
            payerSummary: collection == nil ? nil : .init(payerCount: 0, paidCount: 0, nativeAmountDue: 0, nativeAmountPaid: paid)
        )
    }

    private func collection(status: GroupPaymentRequest.Status = .open, paid: Double = 0, amount: GroupPaymentRequest.Collection.PaymentAmount? = .fixed(.init(nativeAmount: 10))) -> GroupPaymentRequest {
        request(id: 1, split: nil, collection: .init(
            text: nil,
            currency: "usd",
            endsAt: nil,
            paymentAmount: amount
        ), status: status, paid: paid)
    }

    private var split: GroupPaymentRequest {
        request(id: 2, split: .init(
            text: .plaintext(title: "Dinner", description: ""),
            currency: "usd",
            endsAt: now.addingTimeInterval(86_400),
            shares: [.init(userID: creator, nativeAmount: 10, settlement: .creator), .init(userID: viewer, nativeAmount: 10)]
        ), collection: nil)
    }

    private func store(holding requests: [GroupPaymentRequest], showsCollections: Bool) -> PaymentRequests {
        let store = PaymentRequests(getChatPage: { _, _, _ in [] }, getRequest: { _ in throw ErrorGetPaymentRequest.unknown }, showsCollections: { showsCollections })
        store.ingest(requests)
        return store
    }

    // MARK: - Flag off -

    @Test("With the flag off, a collection's widget is unsupported; a split's is a card")
    func flagOffCardState() {
        let collection = collection()
        let store = store(holding: [collection, split], showsCollections: false)

        #expect(store.cardState(for: collection.id, in: chat, sentBy: creator, copy: copy, now: now) == .unsupported)
        guard case .card = store.cardState(for: split.id, in: chat, sentBy: creator, copy: copy, now: now) else {
            Issue.record("expected the split to draw as a card"); return
        }
    }

    @Test("With the flag off, an open collection is not in the deck or the timelines")
    func flagOffDeckAndTimelines() {
        let store = store(holding: [collection(), split], showsCollections: false)

        #expect(store.deck(for: chat, viewer: viewer, at: now).map(\.id) == [split.id])
        #expect(store.deckItems(for: chat, viewer: viewer, order: PaymentRequestDeckOrder(), copy: copy, now: now).map(\.request.id) == [split.id])
        #expect(Set(store.timelines(in: chat).keys) == [split.id])
    }

    // MARK: - Flag on -

    @Test("With the flag on, an open collection's card reads its amount each and its total paid, with no bar or status")
    func flagOnOpenCard() {
        let collection = collection(paid: 30)
        let store = store(holding: [collection], showsCollections: true)

        #expect(store.cardState(for: collection.id, in: chat, sentBy: creator, copy: copy, now: now) == .card(.init(
            title: "$10 each",
            progressLine: "$30 paid",
            fraction: nil,
            statusLine: "",
            isEnded: false
        )))
    }

    @Test("With the flag on, a closed collection's card says Closed")
    func flagOnClosedCard() {
        let collection = collection(status: .closed)
        let store = store(holding: [collection], showsCollections: true)

        guard case .card(let card) = store.cardState(for: collection.id, in: chat, sentBy: creator, copy: copy, now: now) else {
            Issue.record("expected a card"); return
        }
        #expect(card.title == "$10 each")
        #expect(card.progressLine == "$0 paid")
        #expect(card.statusLine == "Closed")
        #expect(card.fraction == nil)
    }

    @Test("With the flag on, a collection whose amount kind this build doesn't know is unsupported")
    func flagOnUnknownAmount() {
        let collection = collection(amount: nil)
        let store = store(holding: [collection], showsCollections: true)

        #expect(store.cardState(for: collection.id, in: chat, sentBy: creator, copy: copy, now: now) == .unsupported)
    }

    @Test("With the flag on, a split still draws its split card")
    func flagOnSplitCard() {
        let store = store(holding: [split], showsCollections: true)

        guard case .card(let card) = store.cardState(for: split.id, in: chat, sentBy: creator, copy: copy, now: now) else {
            Issue.record("expected the split to draw as a card"); return
        }
        #expect(card.title == "Dinner")
        #expect(card.fraction != nil)
    }

    @Test("With the flag on, nothing is in the deck, and a collection's rows tap through with no title")
    func flagOnDeckAndTimelines() {
        let collection = collection()
        let store = store(holding: [collection, split], showsCollections: true)

        #expect(store.deck(for: chat, viewer: viewer, at: now).isEmpty)
        #expect(store.deckItems(for: chat, viewer: viewer, order: PaymentRequestDeckOrder(), copy: copy, now: now).isEmpty)
        let timelines = store.timelines(in: chat)
        #expect(Set(timelines.keys) == [collection.id, split.id])
        #expect(timelines[collection.id]?.title == nil)
        #expect(timelines[split.id]?.title == "Dinner")
    }
}
