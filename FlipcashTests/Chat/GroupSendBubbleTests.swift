//
//  GroupSendBubbleTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite("Group send bubble lines")
struct GroupSendBubbleTests {

    private let me = UserID()
    private let alex = UserID()
    private let sam = UserID()
    private let kim = UserID()
    private let usd = { (value: Decimal) in FiatAmount(value: value, currency: .usd) }

    private func payment(_ id: UserID, _ amount: Double) -> CashPayment {
        CashPayment(receiverID: id, nativeAmount: amount, quarks: UInt64(amount * 1_000_000))
    }

    @Test("an even split shows the shared part")
    func evenSplit() throws {
        let lines = try #require(ChatItem.groupSend(
            [payment(alex, 1), payment(sam, 1)],
            total: usd(2), shownAs: usd(2), sender: "You", selfUserID: me
        ))
        #expect(lines.caption == "You sent to 2 people")
        #expect(lines.each == "$1.00 Each")
        #expect(lines.received == nil)
    }

    @Test("an uneven split shows the smallest part with a tilde, and a paid viewer their own part")
    func unevenSplitPaidViewer() throws {
        let lines = try #require(ChatItem.groupSend(
            [payment(alex, 0.34), payment(me, 0.33), payment(kim, 0.33)],
            total: usd(1), shownAs: usd(1), sender: "Sam", selfUserID: me
        ))
        #expect(lines.caption == "Sam sent to 3 people")
        #expect(lines.each == "~$0.33 Each")
        #expect(lines.received == "You received $0.33")
    }

    @Test("parts are restated in the viewer's currency by their share of the total")
    func restatedParts() throws {
        let lines = try #require(ChatItem.groupSend(
            [payment(alex, 1), payment(me, 1)],
            total: usd(2), shownAs: FiatAmount(value: 3, currency: .cad), sender: "Sam", selfUserID: me
        ))
        #expect(lines.received == "You received " + FiatAmount(value: 1.5, currency: .cad).formatted())
    }

    @Test("a payment to one member draws as a plain cash card")
    func singleRecipient() {
        #expect(ChatItem.groupSend(
            [payment(alex, 1)], total: usd(1), shownAs: usd(1), sender: "You", selfUserID: me
        ) == nil)
    }
}

@Suite("Group send details sheet")
struct GroupSendDetailsTests {

    private let me = UserID()
    private let alex = UserID()
    private let unknown = UserID()

    private func cash(sender: UserID, _ payments: [CashPayment]) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: 1),
            senderID: sender,
            content: .cash(ExchangedFiat(
                onChainAmount: TokenAmount(quarks: 1_000_000, mint: .usdf),
                nativeAmount: FiatAmount(value: 1, currency: .usd),
                currencyRate: Rate(fx: 1, currency: .usd)
            )),
            cashPayments: payments,
            date: Date(timeIntervalSince1970: 1),
            unreadSeq: 1
        )
    }

    @Test("recipients are named in payment order, the viewer as You and anyone unrostered as Someone")
    func names() throws {
        let details = try #require(GroupSendDetails(
            message: cash(sender: alex, [
                CashPayment(receiverID: me, nativeAmount: 0.5, quarks: 500_000),
                CashPayment(receiverID: unknown, nativeAmount: 0.5, quarks: 500_000),
            ]),
            members: [ConversationMember(userID: alex, displayName: "Alex")],
            selfUserID: me
        ))
        #expect(details.from == "Alex")
        #expect(details.recipients == ["You", "Someone"])
        #expect(details.total == "$1.00")
    }

    @Test("a payment to one member has no group details")
    func singleRecipient() {
        #expect(GroupSendDetails(
            message: cash(sender: me, [CashPayment(receiverID: alex, nativeAmount: 1, quarks: 1_000_000)]),
            members: [],
            selfUserID: me
        ) == nil)
    }
}
