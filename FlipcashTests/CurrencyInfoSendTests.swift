//
//  CurrencyInfoSendTests.swift
//  FlipcashTests
//

import Testing
import Foundation
import FlipcashCore
@testable import Flipcash

@Suite("Currency Info send")
struct CurrencyInfoSendTests {

    // MARK: - Tiles and More rows

    @Test("A held currency offers Send, Buy, Transactions and More")
    func heldTiles() {
        #expect(CurrencyInfoActions.tiles(isOwned: true, isUSDF: false) == [.send, .buy, .transactions, .more])
    }

    @Test("USDF drops Buy")
    func usdfTiles() {
        #expect(CurrencyInfoActions.tiles(isOwned: true, isUSDF: true) == [.send, .transactions, .more])
    }

    @Test("A currency that isn't held offers only Buy In")
    func notHeldTiles() {
        #expect(CurrencyInfoActions.tiles(isOwned: false, isUSDF: false) == [.buyIn])
    }

    @Test("More lists Convert, Withdraw and Deposit, and USDF has no Deposit")
    func moreRows() {
        #expect(CurrencyInfoActions.moreRows(isUSDF: false) == [.convert, .withdraw, .deposit])
        #expect(CurrencyInfoActions.moreRows(isUSDF: true) == [.convert, .withdraw, .deposit])
    }

    @Test("More row subtitles name the currency")
    func moreSubtitles() {
        #expect(CurrencyInfoActions.subtitle(for: .withdraw, name: "Jeffy") == "Withdraw Jeffy to a different Solana crypto wallet")
    }

    // MARK: - Select Recipient

    private let me = UUID()

    private func chat(_ n: UInt8, type: ConversationType, name: String, handle: String? = nil) -> Conversation {
        let other = UUID()
        return Conversation(
            id: .test(n),
            members: [
                ConversationMember(userID: me, displayName: "Me"),
                ConversationMember(userID: other, displayName: name, username: handle.flatMap { Username($0) }),
            ],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: Double(n)),
            type: type,
            title: type == .group ? name : nil
        )
    }

    private func names(_ chats: [Conversation]) -> [String] {
        chats.map { $0.counterpart(excluding: me)?.displayName ?? "" }
    }

    @Test("Groups are left out and the chat list's order is kept")
    func dmOnlyInOrder() {
        let chats = [
            chat(3, type: .group, name: "Builders"),
            chat(2, type: .contactDm, name: "Bea"),
            chat(1, type: .contactDm, name: "Al"),
        ]
        let result = CurrencySendRecipients.recipients(in: chats, query: "", selfUserID: me) {
            $0.counterpart(excluding: me)?.displayName ?? ""
        }
        #expect(names(result) == ["Bea", "Al"])
    }

    @Test("Search matches a name or a username, with or without @")
    func search() {
        let chats = [
            chat(2, type: .contactDm, name: "Bea", handle: "bee"),
            chat(1, type: .contactDm, name: "Al", handle: "alpha"),
        ]
        let name: (Conversation) -> String = { $0.counterpart(excluding: me)?.displayName ?? "" }
        #expect(names(CurrencySendRecipients.recipients(in: chats, query: " al ", selfUserID: me, name: name)) == ["Al"])
        #expect(names(CurrencySendRecipients.recipients(in: chats, query: "@bee", selfUserID: me, name: name)) == ["Bea"])
        #expect(CurrencySendRecipients.recipients(in: chats, query: "zzz", selfUserID: me, name: name).isEmpty)
    }

    // MARK: - Send hand-off

    @Test("Leaving the flow waits for the sheet to dismiss after a send")
    func handoffAfterSend() {
        var handoff = CurrencySendHandoff()
        handoff.sendSucceeded()
        let first = handoff.sheetDidDismiss()
        let second = handoff.sheetDidDismiss()
        #expect(first)
        #expect(!second)
    }

    @Test("A sheet closed without a send returns to the list")
    func handoffWithoutSend() {
        var handoff = CurrencySendHandoff()
        let left = handoff.sheetDidDismiss()
        #expect(!left)
    }

    // MARK: - Community chats

    @Test("Row text reads amount, currency and members")
    func communityRowText() {
        #expect(CommunityChats.subtitle(amount: "$10,840", currencyName: "Jeffy", memberCount: 44) == "$10,840 of Jeffy held by 44 members")
        #expect(CommunityChats.subtitle(amount: "$5", currencyName: "Jeffy", memberCount: 1) == "$5 of Jeffy held by 1 member")
        #expect(CommunityChats.subtitle(amount: nil, currencyName: "Jeffy", memberCount: 3) == "3 members")
    }

    @Test("A curve-valued holding with a sub-cent remainder still drops its zero fraction")
    func communityHoldingsRounding() {
        let mint = PublicKey.generate()!
        let value = ExchangedFiat.compute(
            onChainAmount: TokenAmount(quarks: 123_456_789_012, mint: mint),
            rate: Rate(fx: 1, currency: .usd),
            supplyQuarks: 10_000 * 10_000_000_000
        )
        #expect(value.nativeAmount.value != value.nativeAmount.roundedToSmallestUnit().value)
        #expect(CommunityChats.holdingsText(FiatAmount.usd(111_137.004)) == "$111,137")
        #expect(CommunityChats.holdingsText(FiatAmount.usd(2.504)) == "$2.50")
        #expect(!CommunityChats.holdingsText(value.nativeAmount).contains(".00"))
    }

    @Test("The section previews three chats and is empty when there are none")
    func communityPreview() {
        let chats = (1...5).map { chat(UInt8($0), type: .group, name: "G\($0)") }
        #expect(CommunityChats.preview(chats).count == 3)
        #expect(CommunityChats.preview([]).isEmpty)
    }
}

@Suite("PaymentSuccess")
struct PaymentSuccessTests {

    @Test("The payment hold is one second")
    func holdIsOneSecond() {
        #expect(PaymentSuccess.hold == .seconds(1))
    }

    @Test("Release runs after the hold, not before")
    func releasesAfterHold() async {
        var events: [String] = []
        await PaymentSuccess.release(after: .milliseconds(20)) { events.append("release") }
        events.append("after")
        #expect(events == ["release", "after"])
    }

    @Test("A cancelled hold does not release")
    func cancelledHoldSkipsRelease() async {
        let task = Task { () -> Bool in
            var released = false
            await PaymentSuccess.release(after: .seconds(5)) { released = true }
            return released
        }
        task.cancel()
        #expect(await task.value == false)
    }
}
