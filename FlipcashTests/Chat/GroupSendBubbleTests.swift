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

    private var names: [UserID: String] { [alex: "Alex Morgan", sam: "Sam Chen", kim: "Kim Lee"] }

    private func lines(
        _ payments: [CashPayment],
        receiver: UserID? = nil,
        total: Decimal,
        shownAs: FiatAmount? = nil,
        sender: String
    ) -> ChatCashContent.GroupSend? {
        ChatItem.groupSend(
            payments, receiver: receiver, total: usd(total), shownAs: shownAs ?? usd(total),
            sender: sender, selfUserID: me, nameOf: { names[$0] }
        )
    }

    @Test("an even split shows the shared part and names the first recipient")
    func evenSplit() throws {
        let lines = try #require(lines([payment(alex, 1), payment(sam, 1)], total: 2, sender: "You"))
        #expect(lines.caption == "You sent")
        #expect(lines.each == "$1.00 Each")
        #expect(lines.received == nil)
        #expect(lines.recipients == "to Alex Morgan and 1 Other")
    }

    @Test("an uneven split shows the smallest part with a tilde, and a paid viewer their own part")
    func unevenSplitPaidViewer() throws {
        let lines = try #require(lines([payment(alex, 0.34), payment(me, 0.33), payment(kim, 0.33)], total: 1, sender: "Sam Chen"))
        #expect(lines.caption == "Sam Chen sent")
        #expect(lines.each == "~$0.33 Each")
        #expect(lines.received == "You received $0.33")
        #expect(lines.recipients == "to Alex Morgan and 2 Others")
    }

    @Test("an unnamed first recipient falls back to a count")
    func unnamedRecipient() throws {
        let lines = try #require(lines([payment(UserID(), 1), payment(sam, 1)], total: 2, sender: "You"))
        #expect(lines.recipients == "to 2 people")
    }

    @Test("parts are restated in the viewer's currency by their share of the total")
    func restatedParts() throws {
        let lines = try #require(lines([payment(alex, 1), payment(me, 1)], total: 2, shownAs: FiatAmount(value: 3, currency: .cad), sender: "Sam"))
        #expect(lines.received == "You received " + FiatAmount(value: 1.5, currency: .cad).formatted())
    }

    @Test("a payment to one member names them, with no per-person line")
    func singleRecipient() throws {
        let lines = try #require(lines([], receiver: alex, total: 1, sender: "You"))
        #expect(lines.caption == "You sent")
        #expect(lines.each == nil)
        #expect(lines.recipients == "to Alex Morgan")
    }

    @Test("a payment to the viewer alone, or to no known member, keeps the plain card")
    func plainCard() {
        #expect(lines([], receiver: me, total: 1, sender: "Sam") == nil)
        #expect(lines([], receiver: nil, total: 1, sender: "Sam") == nil)
        #expect(lines([], receiver: UserID(), total: 1, sender: "Sam") == nil)
    }
}

@Suite("Group send details sheet")
struct GroupSendDetailsTests {

    private let me = UserID()
    private let alex = UserID()
    private let unknown = UserID()

    private func cash(sender: UserID, receiver: UserID? = nil, _ payments: [CashPayment]) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: 1),
            senderID: sender,
            content: .cash(ExchangedFiat(
                onChainAmount: TokenAmount(quarks: 1_000_000, mint: .usdf),
                nativeAmount: FiatAmount(value: 1, currency: .usd),
                currencyRate: Rate(fx: 1, currency: .usd)
            )),
            cashReceiverID: receiver,
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
        #expect(details.from.name == "Alex")
        #expect(details.recipients.map(\.name) == ["You", "Someone"])
    }

    @Test("a single send names its one receiver")
    func singleReceiver() throws {
        let details = try #require(GroupSendDetails(
            message: cash(sender: me, receiver: alex, []),
            members: [ConversationMember(userID: alex, displayName: "Alex")],
            selfUserID: me
        ))
        #expect(details.from.name == "You")
        #expect(details.recipients.map(\.name) == ["Alex"])
    }

    @Test("a payment that names no receiver has no details")
    func singleRecipient() {
        #expect(GroupSendDetails(
            message: cash(sender: me, [CashPayment(receiverID: alex, nativeAmount: 1, quarks: 1_000_000)]),
            members: [],
            selfUserID: me
        ) == nil)
    }
}
