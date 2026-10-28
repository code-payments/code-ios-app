//
//  PaymentRequestPreviewTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import FlipcashCore

@Suite("Notification preview of a payment request")
struct PaymentRequestPreviewTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let creator = UUID()
    private let viewer = UUID()
    private let requestID = PaymentRequestID(data: Data(repeating: 7, count: 32))
    private let copy = PaymentRequestCopy(displayCurrency: .usd, rates: [:])

    private func request(text: GroupPaymentRequest.Text?) -> GroupPaymentRequest {
        GroupPaymentRequest(
            id: requestID,
            creator: creator,
            createdAt: now.addingTimeInterval(-60),
            status: .open,
            closedAt: nil,
            version: 1,
            chatID: ConversationID(data: Data(repeating: 1, count: 32)),
            split: .init(
                text: text,
                currency: "usd",
                endsAt: now.addingTimeInterval(3 * 24 * 3600),
                shares: [
                    .init(userID: creator, nativeAmount: 20, settlement: .creator),
                    .init(userID: viewer, nativeAmount: 20),
                    .init(userID: UUID(), nativeAmount: 20),
                ]
            )
        )
    }

    private func preview(_ request: GroupPaymentRequest, viewer: UUID? = nil, sender: String? = "Sam Rivera") -> PaymentRequestPreview {
        PaymentRequestPreview(request: request, seal: nil, viewer: viewer ?? self.viewer, senderName: sender, copy: copy, now: now)
    }

    @Test("A titled request words the banner with the viewer's share and fills the card")
    func titleAndAmount() {
        let result = preview(request(text: .plaintext(title: "Dinner", description: "")))

        #expect(result.body == "Sam sent request for Dinner · $20")
        #expect(result.card?.title == "Dinner")
        #expect(result.card?.progressLine == "$20 paid, $60 requested")
    }

    @Test("Someone without a share sees the request's total")
    func totalForNonParticipant() {
        let result = preview(request(text: .plaintext(title: "Dinner", description: "")), viewer: UUID())

        #expect(result.body == "Sam sent request for Dinner · $60")
    }

    @Test("A title that can't be opened keeps the amount and leaves the card empty")
    func noTitle() {
        let sealed = GroupPaymentRequest.Text.encrypted(scheme: 1, nonce: Data([1]), ciphertext: Data([2]))
        let result = preview(request(text: sealed))

        #expect(result.body == "Sam sent request · $20")
        #expect(result.card == nil)
    }

    @Test("Without a sender name the line opens on the request")
    func noSender() {
        let result = preview(request(text: .plaintext(title: "Dinner", description: "")), sender: nil)

        #expect(result.body == "Request for Dinner · $20")
    }

    @Test("The transcript row carries the fetched card, and stays card-less without one")
    func transcriptCard() throws {
        let fetched = try #require(preview(request(text: .plaintext(title: "Dinner", description: ""))).card)
        let message = ConversationMessage(
            id: MessageID(value: 1),
            senderID: creator,
            content: .widget(.paymentRequest(requestID)),
            date: now,
            unreadSeq: 1
        )

        func card(_ cards: [PaymentRequestID: ChatPaymentRequestContent.Card]) -> ChatPaymentRequestContent.Card?? {
            let items = ChatItem.preview(from: [message], selfUserID: viewer, paymentRequestCards: cards)
            for case .message(let row) in items {
                if case .paymentRequest(let content) = row.content { return .some(content.card) }
            }
            return nil
        }

        #expect(card([requestID: fetched]) == .some(.some(fetched)))
        // A failed lookup leaves the map empty: today's card-less row.
        #expect(card([:]) == .some(nil))
    }
}
