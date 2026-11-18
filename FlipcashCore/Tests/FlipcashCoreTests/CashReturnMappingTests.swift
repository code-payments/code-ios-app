//
//  CashReturnMappingTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashAPI
@testable import FlipcashCore

@Suite("Cash return mapping")
struct CashReturnMappingTests {

    private let chatID = ConversationID(data: Data(repeating: 0xAB, count: 32))

    @Test("A cash message without payment_return has no return state")
    func absentReturn() {
        #expect(CashReturn(Flipcash_Messaging_V1_CashContent()) == nil)
    }

    @Test("An empty Offer is an offer")
    func offer() {
        let proto = Flipcash_Messaging_V1_CashContent.with { $0.paymentReturn = .with { $0.offer = .init() } }
        #expect(CashReturn(proto) == CashReturn(hasOffer: true, returnOf: nil))
    }

    @Test("return_of names the returned message, independent of the offer")
    func returnOf() {
        let proto = Flipcash_Messaging_V1_CashContent.with {
            $0.paymentReturn = .with { $0.returnOf = .with { $0.messageID = .with { $0.value = 9 } } }
        }
        #expect(CashReturn(proto) == CashReturn(hasOffer: false, returnOf: .init(messageID: MessageID(value: 9))))
    }

    @Test("Return status maps each state and carries the intent id only when set")
    func statusMapping() throws {
        let intentID = Data(repeating: 0x07, count: 32)
        let available = Flipcash_Messaging_V1_GetCashMessageReturnStatusResponse.with {
            $0.status = .available
            $0.paymentIntentID = .with { $0.value = intentID }
        }
        #expect(try ChatMessagingService.cashMessageReturnStatusResult(available).get()
            == CashReturnStatus(state: .available, paymentIntentID: intentID))

        let returned = Flipcash_Messaging_V1_GetCashMessageReturnStatusResponse.with { $0.status = .returned }
        #expect(try ChatMessagingService.cashMessageReturnStatusResult(returned).get()
            == CashReturnStatus(state: .returned, paymentIntentID: nil))
    }

    @Test("Result codes map positionally onto the error enum")
    func resultMapping() {
        for (result, expected) in [
            (Flipcash_Messaging_V1_GetCashMessageReturnStatusResponse.Result.denied, ErrorGetCashMessageReturnStatus.denied),
            (.notFound, .notFound),
        ] {
            let response = Flipcash_Messaging_V1_GetCashMessageReturnStatusResponse.with { $0.result = result }
            #expect(throws: expected) { try ChatMessagingService.cashMessageReturnStatusResult(response).get() }
        }
    }

    @Test("Send and receive notifications both surface returned_payment")
    func activityReturnedPayment() {
        let payment = Flipcash_Activity_V1_ReturnedPayment.with {
            $0.chatID = chatID.proto
            $0.messageID = .with { $0.value = 5 }
        }
        let expected = Activity.ReturnedPayment(conversationID: chatID, messageID: MessageID(value: 5))

        let sent = Flipcash_Activity_V1_Notification.OneOf_AdditionalMetadata.directlySentCrypto(.with { $0.returnedPayment = payment })
        let received = Flipcash_Activity_V1_Notification.OneOf_AdditionalMetadata.receivedCrypto(.with { $0.returnedPayment = payment })
        #expect(Activity.ReturnedPayment(sent) == expected)
        #expect(Activity.ReturnedPayment(received) == expected)
        #expect(Activity.ReturnedPayment(nil) == nil)
    }
}
