//
//  GroupSendBubbleTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite("Cash card lines")
struct CashCardLinesTests {

    private let me = UserID()
    private let alex = UserID()
    private let sam = UserID()
    private let kim = UserID()
    private let usd = { (value: Decimal) in FiatAmount(value: value, currency: .usd) }

    private func payment(_ id: UserID?, _ amount: Double) -> CashPayment {
        CashPayment(receiverID: id, nativeAmount: amount, quarks: UInt64(amount * 1_000_000))
    }

    private var names: [UserID: String] { [alex: "Alex Morgan", sam: "Sam Chen", kim: "Kim Lee"] }

    private struct Card: Equatable {
        let caption: String
        let amount: String
        let total: String?
        let counterpart: String
    }

    private func card(
        _ payments: [CashPayment] = [],
        receiver: UserID? = nil,
        fromSelf: Bool,
        tip: Bool = false,
        inGroup: Bool = true,
        total: Decimal,
        shownAs: FiatAmount? = nil,
        sender: String? = "Fred Wilson",
        counterpart: String = ""
    ) -> Card {
        let result = ChatItem.cashCard(
            payments, receiver: receiver, isFromSelf: fromSelf, isTip: tip, inGroup: inGroup,
            total: usd(total), shownAs: shownAs ?? usd(total), sender: sender,
            counterpartName: counterpart, selfUserID: me, nameOf: { names[$0] }
        )
        return Card(caption: result.lines.caption, amount: result.amount, total: result.lines.total, counterpart: result.lines.counterpart)
    }

    private var three: [CashPayment] { [payment(alex, 1), payment(sam, 1), payment(kim, 1)] }

    // MARK: Group send to two or more

    @Test("the sender sees the part each got, the total, and the first recipient")
    func groupSender() {
        #expect(card(three, fromSelf: true, total: 3, sender: nil)
            == Card(caption: "You sent", amount: "$1.00", total: "$3.00 total", counterpart: "to Alex Morgan and 2 others"))
    }

    @Test("one other recipient reads 'other'")
    func groupSender_twoRecipients() {
        #expect(card([payment(alex, 1), payment(sam, 1)], fromSelf: true, total: 2).counterpart == "to Alex Morgan and 1 other")
    }

    @Test("a paid viewer is named in the caption and the sender in the footer")
    func groupRecipient() {
        #expect(card([payment(alex, 1), payment(me, 1), payment(kim, 1)], fromSelf: false, total: 3)
            == Card(caption: "You and 2 others received", amount: "$1.00", total: "$3.00 total", counterpart: "from Fred Wilson"))
        #expect(card([payment(me, 1), payment(kim, 1)], fromSelf: false, total: 2).caption == "You and 1 other received")
    }

    @Test("a member who wasn't paid sees who sent it and the first recipient")
    func groupMemberNotPaid() {
        #expect(card(three, fromSelf: false, total: 3)
            == Card(caption: "Fred Wilson sent", amount: "$1.00", total: "$3.00 total", counterpart: "to Alex Morgan and 2 others"))
    }

    @Test("an unnamed first recipient falls back to a count")
    func groupUnnamedLead() {
        #expect(card([payment(UserID(), 1), payment(sam, 1)], fromSelf: true, total: 2).counterpart == "to 2 people")
        #expect(card([payment(nil, 1), payment(sam, 1)], fromSelf: false, total: 2).counterpart == "to 2 people")
    }

    @Test("an unnamed sender reads Someone")
    func groupUnnamedSender() {
        #expect(card(three, fromSelf: false, total: 3, sender: nil).caption == "Someone sent")
        #expect(card([payment(me, 1), payment(kim, 1)], fromSelf: false, total: 2, sender: "").counterpart == "from Someone")
    }

    @Test("the part is restated in the viewer's currency by its share of the total")
    func groupRestatedPart() {
        let result = card([payment(alex, 1), payment(me, 1)], fromSelf: false, total: 2, shownAs: FiatAmount(value: 3, currency: .cad))
        #expect(result.amount == FiatAmount(value: 1.5, currency: .cad).formatted())
        #expect(result.total == FiatAmount(value: 3, currency: .cad).formatted() + " total")
    }

    // MARK: Group send to one person

    @Test("a send to one member draws the DM layout for the sender")
    func singleSender() {
        #expect(card(receiver: alex, fromSelf: true, total: 5)
            == Card(caption: "You sent", amount: "$5.00", total: nil, counterpart: "to Alex Morgan"))
    }

    @Test("the one member paid sees who it came from")
    func singleRecipient() {
        #expect(card(receiver: me, fromSelf: false, total: 5)
            == Card(caption: "You received", amount: "$5.00", total: nil, counterpart: "from Fred Wilson"))
    }

    @Test("a member who wasn't paid sees who sent it to whom")
    func singleMemberNotPaid() {
        #expect(card(receiver: alex, fromSelf: false, total: 5)
            == Card(caption: "Fred Wilson sent", amount: "$5.00", total: nil, counterpart: "to Alex Morgan"))
    }

    @Test("a single payment part is read as its receiver")
    func singlePart() {
        #expect(card([payment(me, 5)], fromSelf: false, total: 5).caption == "You received")
        #expect(card([payment(alex, 5)], fromSelf: false, total: 5).counterpart == "to Alex Morgan")
    }

    @Test("a receiver nobody can name reads Someone, and never tells the viewer they were paid")
    func singleUnknownReceiver() {
        #expect(card(receiver: UserID(), fromSelf: false, total: 5)
            == Card(caption: "Fred Wilson sent", amount: "$5.00", total: nil, counterpart: "to Someone"))
        #expect(card(receiver: nil, fromSelf: false, total: 5).caption == "Fred Wilson sent")
        #expect(card(receiver: nil, fromSelf: true, total: 5).counterpart == "to Someone")
    }

    // MARK: DM

    @Test("a DM sender sees who they paid")
    func dmSender() {
        #expect(card(fromSelf: true, inGroup: false, total: 5, counterpart: "Noah Parker")
            == Card(caption: "You sent", amount: "$5.00", total: nil, counterpart: "to Noah Parker"))
    }

    @Test("a DM recipient sees who paid them")
    func dmRecipient() {
        #expect(card(fromSelf: false, inGroup: false, total: 5, counterpart: "Noah Parker")
            == Card(caption: "You received", amount: "$5.00", total: nil, counterpart: "from Noah Parker"))
    }

    @Test("an unnamed DM counterpart reads Someone")
    func dmUnnamed() {
        #expect(card(fromSelf: false, inGroup: false, total: 5).counterpart == "from Someone")
        #expect(card(fromSelf: true, inGroup: false, total: 5).counterpart == "to Someone")
    }

    // MARK: Tips

    @Test("a sent tip reads 'You tipped' and a received one 'You received'")
    func tips() {
        #expect(card(fromSelf: true, tip: true, inGroup: false, total: 1, counterpart: "Noah").caption == "You tipped")
        #expect(card(fromSelf: false, tip: true, inGroup: false, total: 1, counterpart: "Noah").caption == "You received")
        #expect(card(receiver: alex, fromSelf: true, tip: true, total: 1).caption == "You tipped")
        #expect(card(receiver: me, fromSelf: false, tip: true, total: 1).caption == "You received")
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
        #expect(details.recipients.map(\.isSelf) == [true, false])
    }

    @Test("a single send names its one receiver")
    func singleReceiver() throws {
        let details = try #require(GroupSendDetails(
            message: cash(sender: me, receiver: alex, []),
            members: [ConversationMember(userID: alex, displayName: "Alex")],
            selfUserID: me
        ))
        #expect(details.from.name == "You")
        #expect(details.from.isSelf)
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
