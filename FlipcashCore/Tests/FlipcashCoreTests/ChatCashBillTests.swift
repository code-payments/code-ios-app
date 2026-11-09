//
//  ChatCashBillTests.swift
//  FlipcashCoreTests
//

import Testing
import Foundation
@testable import FlipcashCore

@Suite("Chat cash bill trigger")
struct ChatCashBillTests {

    private let me = UUID()
    private let them = UUID()
    private let third = UUID()
    private let chatA = ConversationID(data: Data(repeating: 0xA1, count: 32))
    private let chatB = ConversationID(data: Data(repeating: 0xB2, count: 32))

    private func cash(
        from sender: UUID? = nil,
        id: UInt64 = 10,
        amount: FiatAmount = .usd(20),
        receiver: UUID? = nil,
        payments: [CashPayment] = [],
        action: CashAction = .sent,
        requestID: PaymentRequestID? = nil,
        cashReturn: CashReturn? = nil
    ) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id), senderID: sender ?? them,
            content: .cash(ExchangedFiat(nativeAmount: amount, rate: .oneToOne)),
            cashAction: action, cashReceiverID: receiver, cashPayments: payments,
            paymentRequestID: requestID, cashReturn: cashReturn,
            date: Date(timeIntervalSince1970: 2_000_000), unreadSeq: 1
        )
    }

    private func context(
        source: ChatCashBill.Source = .live,
        in conversation: ConversationID? = nil,
        open: ConversationID?? = nil,
        countedThrough: MessageID? = MessageID(value: 5),
        flag: Bool = true,
        onTop: Bool = false,
        busy: Bool = false
    ) -> ChatCashBill.Context {
        ChatCashBill.Context(
            source: source, selfUserID: me,
            messageConversationID: conversation ?? chatA,
            openConversationID: open ?? chatA,
            countedThrough: countedThrough,
            flagEnabled: flag, somethingOnTop: onTop, billBusy: busy
        )
    }

    private func amount(_ message: ConversationMessage, _ context: ChatCashBill.Context) -> Decimal? {
        ChatCashBill.billAmount(for: message, in: context)?.nativeAmount.value
    }

    // 1
    @Test("Live cash from someone else to me shows a bill of the message amount")
    func liveCashToMe() {
        #expect(amount(cash(receiver: me), context()) == 20)
    }

    // 2
    @Test("My own send never shows a bill")
    func ownSend() {
        #expect(amount(cash(from: me, receiver: them), context()) == nil)
    }

    // 3
    @Test("A group send shows my share, not the total")
    func groupShare() throws {
        let payments = [
            CashPayment(receiverID: third, nativeAmount: 5, quarks: 5_000_000),
            CashPayment(receiverID: me, nativeAmount: 7.5, quarks: 7_500_000),
            CashPayment(receiverID: UUID(), nativeAmount: 7.5, quarks: 7_500_000),
        ]
        let message = cash(amount: .usd(20), payments: payments)
        let share = try #require(ChatCashBill.billAmount(for: message, in: context()))
        #expect(share.nativeAmount.value == Decimal(string: "7.5"))
        #expect(share.onChainAmount.quarks == 7_500_000)
        #expect(share.nativeAmount.currency == .usd)
    }

    // 4
    @Test("A group send that does not list me shows nothing")
    func groupNotAReceiver() {
        let payments = [
            CashPayment(receiverID: third, nativeAmount: 10, quarks: 10_000_000),
            CashPayment(receiverID: UUID(), nativeAmount: 10, quarks: 10_000_000),
        ]
        #expect(amount(cash(payments: payments), context()) == nil)
    }

    @Test("A single-receiver send to someone else shows nothing")
    func singleReceiverNotMe() {
        #expect(amount(cash(receiver: third), context()) == nil)
    }

    @Test("A legacy DM cash message with no receiver on record pays me in full")
    func legacyNoReceiver() {
        #expect(amount(cash(), context()) == 20)
    }

    @Test("Text is never a payment")
    func textMessage() {
        let text = ConversationMessage(
            id: MessageID(value: 10), senderID: them, content: .text("hi"),
            date: Date(timeIntervalSince1970: 2_000_000), unreadSeq: 1
        )
        #expect(ChatCashBill.billAmount(for: text, in: context()) == nil)
    }

    // 5
    @Test("Cash in a chat that is not the open one shows nothing")
    func otherChat() {
        #expect(amount(cash(receiver: me), context(in: chatB)) == nil)
    }

    // 6
    @Test("With no chat open nothing shows")
    func noChatOpen() {
        #expect(amount(cash(receiver: me), context(open: .some(nil))) == nil)
    }

    // 7
    @Test("Catch-up, delta and initial-load deliveries show nothing")
    func catchUp() {
        #expect(amount(cash(receiver: me), context(source: .catchUp)) == nil)
    }

    @Test("A re-delivery at or below the stored watermark shows nothing")
    func redelivery() {
        #expect(amount(cash(id: 5, receiver: me), context(countedThrough: MessageID(value: 5))) == nil)
        #expect(amount(cash(id: 4, receiver: me), context(countedThrough: MessageID(value: 5))) == nil)
        #expect(amount(cash(id: 6, receiver: me), context(countedThrough: MessageID(value: 5))) == 20)
    }

    @Test("The first message in an empty chat has no watermark and still counts")
    func emptyChatFirstMessage() {
        #expect(amount(cash(receiver: me), context(countedThrough: nil)) == 20)
    }

    // 8, 9
    @Test("Anything over the chat, or the chat inside a sheet, drops the payment")
    func somethingOnTop() {
        #expect(amount(cash(receiver: me), context(onTop: true)) == nil)
    }

    // 10
    @Test("While a chat bill is showing or preparing, further payments are dropped")
    func firstOneWins() {
        #expect(amount(cash(receiver: me), context(busy: true)) == nil)
        // Not queued: once the bill closes, the same message no longer qualifies by being replayed
        // through the live path, because the caller only evaluates each message as it lands.
        #expect(amount(cash(id: 11, receiver: me), context(busy: false)) == 20)
    }

    // 11
    @Test("With the flag off nothing shows")
    func flagOff() {
        #expect(amount(cash(receiver: me), context(flag: false)) == nil)
    }

    // 17
    @Test("A tip, a request payment and a Send Back return each show a bill")
    func tipRequestAndReturn() {
        let tip = cash(receiver: me, action: .tipped)
        let request = cash(receiver: me, requestID: PaymentRequestID(data: Data([1, 2, 3])))
        let sendBack = cash(
            receiver: me,
            cashReturn: CashReturn(hasOffer: false, returnOf: .init(messageID: MessageID(value: 3)))
        )
        for message in [tip, request, sendBack] {
            #expect(amount(message, context()) == 20)
        }
    }
}
