//
//  PaymentRequestCollectionCreateTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite("Group payment requests: creating a collection")
struct PaymentRequestCollectionCreateTests {

    @Test("Send Request asks for the keypad amount from each member, in its currency, with no text or deadline")
    func collectionAsksForTheEnteredAmount() {
        let collection = PaymentRequestCreateViewModel.collection(asking: FiatAmount(value: Decimal(string: "10.25")!, currency: .usd))

        #expect(collection.currency == "usd")
        #expect(collection.text == nil)
        #expect(collection.endsAt == nil)
        #expect(collection.paymentAmount == .fixed(.init(nativeAmount: 10.25)))
    }

    @Test("The store creates the collection it's handed and holds what comes back")
    @MainActor
    func storeCreatesTheCollection() async throws {
        let chat = ConversationID.test(1)
        let asked = PaymentRequestCreateViewModel.collection(asking: FiatAmount(value: 10, currency: .usd))
        var sent: GroupPaymentRequest.Collection?
        let created = GroupPaymentRequest(
            id: PaymentRequestID(data: Data([1])),
            creator: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            status: .open,
            closedAt: nil,
            version: 1,
            chatID: chat,
            split: nil,
            collection: asked,
            payerSummary: .init(payerCount: 0, paidCount: 0, nativeAmountDue: 0, nativeAmountPaid: 0)
        )
        let store = PaymentRequests(
            getChatPage: { _, _, _ in [] },
            getRequest: { _ in throw ErrorGetPaymentRequest.unknown },
            createCollection: { _, _, collection in
                sent = collection
                return created
            }
        )

        let request = try await store.create(idempotencyKey: Data([1]), in: chat, collection: asked)

        #expect(sent == asked)
        #expect(request.id == created.id)
        #expect(store.request(created.id)?.collection == asked)
    }
}
