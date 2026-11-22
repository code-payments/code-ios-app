//
//  GroupCollectionCopyTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashAPI
@testable import FlipcashCore

@Suite("Group collections: card, details copy and create wire form")
struct GroupCollectionCopyTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let copy = PaymentRequestCopy(displayCurrency: .usd, rates: [:])

    private func collection(
        status: GroupPaymentRequest.Status = .open,
        fixed: Double? = 10,
        paid: Double? = nil
    ) -> GroupPaymentRequest {
        GroupPaymentRequest(
            id: PaymentRequestID(data: Data(repeating: 7, count: 32)),
            creator: UUID(),
            createdAt: now.addingTimeInterval(-60),
            status: status,
            closedAt: status == .closed ? now : nil,
            version: 1,
            chatID: ConversationID(data: Data(repeating: 1, count: 32)),
            split: nil,
            collection: .init(
                text: nil,
                currency: "usd",
                endsAt: nil,
                paymentAmount: fixed.map { .fixed(.init(nativeAmount: $0)) }
            ),
            payerSummary: paid.map { .init(payerCount: 0, paidCount: 0, nativeAmountDue: 0, nativeAmountPaid: $0) }
        )
    }

    // MARK: - Card -

    @Test("An open collection's card reads the amount each, the total paid, no bar and no status")
    func openCard() throws {
        let card = try #require(ChatPaymentRequestContent.Card(collection: collection(paid: 30), copy: copy, now: now))
        #expect(card.title == "$10 each")
        #expect(card.progressLine == "$30 paid")
        #expect(card.fraction == nil)
        #expect(card.statusLine == "")
        #expect(card.isEnded == false)
    }

    @Test("A collection nobody has paid reads $0 paid")
    func unpaidCard() throws {
        let card = try #require(ChatPaymentRequestContent.Card(collection: collection(), copy: copy, now: now))
        #expect(card.progressLine == "$0 paid")
    }

    @Test("A closed collection's card reads Closed and greys out")
    func closedCard() throws {
        let card = try #require(ChatPaymentRequestContent.Card(collection: collection(status: .closed, paid: 20), copy: copy, now: now))
        #expect(card.statusLine == "Closed")
        #expect(card.isEnded)
    }

    @Test("A collection with an amount kind this build doesn't know has no card")
    func unknownAmountKind() {
        #expect(ChatPaymentRequestContent.Card(collection: collection(fixed: nil), copy: copy, now: now) == nil)
        #expect(copy.collectionAmount(collection(fixed: nil)) == nil)
        #expect(copy.collectionDetailsAmounts(collection(fixed: nil)) == nil)
    }

    // MARK: - Details header -

    @Test("The details header keeps $0 short and states other amounts in full", arguments: [
        (10.0, nil as Double?, "$0 paid · $10.00 each"),
        (11.0, 22.0, "$22.00 paid · $11.00 each"),
        (10.0, 10.0, "$10.00 paid · $10.00 each"),
    ])
    func detailsHeader(fixed: Double, paid: Double?, expected: String) {
        #expect(copy.collectionDetailsAmounts(collection(fixed: fixed, paid: paid)) == expected)
    }

    @Test("The amount to pay is the fixed amount at full precision")
    func amountToPay() throws {
        let amount = try #require(copy.collectionAmount(collection(fixed: 10)))
        #expect(amount.formatted() == "$10.00")
    }

    // MARK: - Wire form -

    @Test("A collection goes out with its currency and fixed amount, and no text or deadline")
    func createWireForm() {
        let proto = collection(fixed: 12.5).collection!.proto
        #expect(proto.currency == "usd")
        #expect(proto.fixed.nativeAmount == 12.5)
        #expect(proto.text == nil)
        #expect(proto.hasEndsAt == false)
    }
}
