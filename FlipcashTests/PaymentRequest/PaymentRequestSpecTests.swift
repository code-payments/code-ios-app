//
//  PaymentRequestSpecTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

/// The shared test cases from the group-requests spec, numbered as it numbers them.
@MainActor
@Suite("Group payment requests: shared spec cases")
struct PaymentRequestSpecTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let chat = ConversationID.test(1)
    private let creator = UUID()
    private let viewer = UUID()
    private let copy = PaymentRequestCopy(displayCurrency: .usd, rates: [:])

    private func request(
        id: UInt8 = 1,
        shares: Int = 4,
        amount: Double = 10,
        paid: Int = 0,
        status: GroupPaymentRequest.Status = .open,
        endsAt: Date? = nil,
        closedAt: Date? = nil,
        version: UInt64 = 1
    ) -> GroupPaymentRequest {
        let list = (0..<shares).map { index in
            GroupPaymentRequest.Share(
                userID: index == 0 ? creator : (index == 1 ? viewer : UUID()),
                nativeAmount: amount,
                settlement: index < paid ? (index == 0 ? .creator : .manual) : nil
            )
        }
        return GroupPaymentRequest(
            id: PaymentRequestID(data: Data([id])),
            creator: creator,
            createdAt: now.addingTimeInterval(-60),
            status: status,
            closedAt: closedAt,
            version: version,
            chatID: chat,
            split: .init(
                text: .plaintext(title: "Dinner", description: ""),
                currency: "usd",
                endsAt: endsAt ?? now.addingTimeInterval(7 * 24 * 3600),
                shares: list
            )
        )
    }

    private func status(endingIn seconds: TimeInterval) -> String {
        PaymentRequestCopy.statusLine(request(endsAt: now.addingTimeInterval(seconds)).deadline(at: now))
    }

    // MARK: - Amounts -

    @Test("1: 26 shares of $20 with only the creator's paid")
    func onlyCreatorPaid() {
        let r = request(shares: 26, amount: 20, paid: 1)
        #expect(copy.progressLine(r) == "$20 paid, $520 requested")
        #expect(copy.deckAmounts(r) == "$20 of $520")
        #expect(abs(r.paidFraction - 1.0 / 26.0) < 1e-12)
    }

    @Test("2: 4 shares of $10, three paid, CLOSED")
    func closedWithOneUnpaid() {
        let r = request(paid: 3, status: .closed, closedAt: now.addingTimeInterval(-60))
        #expect(copy.progressLine(r) == "$30 paid, $40 requested")
        #expect(PaymentRequestCopy.statusLine(r.deadline(at: now)) == "Closed")
        let unpaid = try! #require(r.split?.shares.last)
        #expect(PaymentRequestCopy.shareStatus(unpaid, requestIsOpen: r.effectiveStatus(at: now) == .open) == "Didn't pay")
    }

    @Test("3: all shares paid")
    func paidInFull() {
        let r = request(paid: 4, status: .completed, closedAt: now.addingTimeInterval(-60))
        #expect(PaymentRequestCopy.statusLine(r.deadline(at: now)) == "Paid in full")
        #expect(r.paidFraction == 1)
        #expect(r.isEnded(at: now))
    }

    // MARK: - Status line -

    @Test("4: 7 days left") func sevenDays() { #expect(status(endingIn: 7 * 86_400) == "7 days left to pay") }
    @Test("5: 6 d 1 h rounds up to 7 days") func sixDaysOneHour() { #expect(status(endingIn: 6 * 86_400 + 3_600) == "7 days left to pay") }
    @Test("6: 23 h 10 min reads 24 hours") func underADay() { #expect(status(endingIn: 23 * 3_600 + 600) == "24 hours left to pay") }
    @Test("22: exactly 24 hours reads in hours") func exactlyADay() { #expect(status(endingIn: 24 * 3_600) == "24 hours left to pay") }
    @Test("7: exactly 1 hour") func oneHour() { #expect(status(endingIn: 3_600) == "1 hour left to pay") }
    @Test("8: 30 s reads 1 minute") func thirtySeconds() { #expect(status(endingIn: 30) == "1 minute left to pay") }

    @Test("9: OPEN past its deadline reads as EXPIRED at ends_at")
    func pastDeadline() {
        let endsAt = now.addingTimeInterval(-1)
        let r = request(endsAt: endsAt)
        #expect(r.effectiveStatus(at: now) == .expired)
        #expect(r.effectiveClosedAt(at: now) == endsAt)
        #expect(PaymentRequestCopy.statusLine(r.deadline(at: now)) == "Expired")
        #expect(r.isEnded(at: now))
    }

    // MARK: - Merge -

    private func store(holding existing: GroupPaymentRequest, thenIngest incoming: GroupPaymentRequest) -> GroupPaymentRequest? {
        let store = PaymentRequests(getChatPage: { _, _, _ in [] }, getRequest: { _ in throw ErrorGetPaymentRequest.unknown })
        store.ingest([existing])
        store.ingest([incoming])
        return store.request(existing.id)
    }

    @Test("10: an older version never replaces a newer one")
    func olderVersion() {
        let kept = store(holding: request(version: 5), thenIngest: request(status: .closed, version: 4))
        #expect(kept?.version == 5)
        #expect(kept?.status == .open)
    }

    @Test("11: at an equal version EXPIRED replaces OPEN")
    func expiredReplacesOpen() {
        #expect(store(holding: request(version: 5), thenIngest: request(status: .expired, version: 5))?.status == .expired)
    }

    @Test("12: at an equal version OPEN never replaces EXPIRED")
    func openKeepsExpired() {
        #expect(store(holding: request(status: .expired, version: 5), thenIngest: request(version: 5))?.status == .expired)
    }

    // MARK: - Deck -

    @Test("13: open by nearest deadline, then ended within 24 h")
    func deckOrder() {
        let twoDays = request(id: 1, endsAt: now.addingTimeInterval(2 * 86_400))
        let fiveDays = request(id: 2, endsAt: now.addingTimeInterval(5 * 86_400))
        let closed = request(id: 3, status: .closed, closedAt: now.addingTimeInterval(-3 * 3_600))
        let expired = request(id: 4, status: .expired, endsAt: now.addingTimeInterval(-30 * 3_600), closedAt: now.addingTimeInterval(-30 * 3_600))

        let deck = GroupPaymentRequest.deckOrder([closed, expired, fiveDays, twoDays], at: now)

        #expect(deck.map(\.id) == [twoDays.id, fiveDays.id, closed.id])
    }

    @Test("23: an OPEN request the viewer owes on sorts before one they have paid")
    func deckOrderOwedFirst() {
        let owedFiveDays = request(id: 1, paid: 1, endsAt: now.addingTimeInterval(5 * 86_400))
        let paidTwoDays = request(id: 2, paid: 2, endsAt: now.addingTimeInterval(2 * 86_400))

        let deck = GroupPaymentRequest.deckOrder([paidTwoDays, owedFiveDays], viewer: viewer, at: now)

        #expect(deck.map(\.id) == [owedFiveDays.id, paidTwoDays.id])
        #expect(owedFiveDays.isOwed(by: viewer, at: now))
        #expect(!paidTwoDays.isOwed(by: viewer, at: now))
        #expect(PaymentRequestCopy.timeLeft(owedFiveDays.deadline(at: now)) == "5 days left")
        #expect(PaymentRequestCopy.owedAccessibilityLabel(share: "$20", title: "Dinner", deadline: owedFiveDays.deadline(at: now), count: 2)
            == "2 requests, You owe $20 for Dinner, 5 days left to pay")
    }

    @Test("24: the creator never owes, and an ended request is never owed")
    func creatorNeverOwes() {
        let open = request(id: 1, paid: 0)
        let expired = request(id: 2, endsAt: now.addingTimeInterval(-60))

        #expect(!open.isOwed(by: creator, at: now))
        #expect(!expired.isOwed(by: viewer, at: now))
    }

    @Test("25: the viewer's only owed share becomes paid, so nothing is owed")
    func owedShareBecomesPaid() {
        let owed = request(id: 1, paid: 1, version: 1)
        let paid = request(id: 1, paid: 2, version: 2)

        #expect(owed.isOwed(by: viewer, at: now))
        #expect(!paid.isOwed(by: viewer, at: now))
    }

    @Test("26: viewer owes and scrolls away, so the strip shrinks into the pill and grows back")
    func stripShrinksWhenScrolledAway() {
        #expect(PaymentRequestDeckStyle.collapsed(owes: true, isScrolledAway: false) == .strip)
        #expect(PaymentRequestDeckStyle.collapsed(owes: true, isScrolledAway: true) == .pill)
        #expect(PaymentRequestDeckStyle.collapsed(owes: false, isScrolledAway: false) == .pill)
    }

    // MARK: - People -

    private func people(count: Int) -> PaymentRequestPeople {
        PaymentRequestPeople(members: [creator] + (1..<count).map { _ in UUID() }, creator: creator)
    }

    @Test("14: everyone selected in a 26-member group")
    func everyone() {
        let p = people(count: 26)
        #expect(p.summaryValue == "Everyone, Including You")
        #expect(p.summarySecondLine == "You'll be marked as paid")
        #expect(p.buttonTitle(amount: "$20") == "Request $20 from 25 People")
        let shares = p.shares(nativeAmount: 20)
        #expect(shares.count == 26)
        #expect(shares.first?.userID == creator)
        #expect(shares.allSatisfy { !$0.isPaid && $0.nativeAmount == 20 })
    }

    @Test("15: the creator and one other")
    func creatorAndOne() {
        var p = people(count: 3)
        p.toggle(p.members[2])
        #expect(p.summaryValue == "1 Person, Including You")
        #expect(p.buttonTitle(amount: "$20") == "Request $20 from 1 Person")
    }

    @Test("16: everyone except the creator")
    func everyoneExceptYou() {
        var p = people(count: 5)
        p.toggle(creator)
        #expect(p.summaryValue == "Everyone Except You")
        #expect(p.summarySecondLine == nil)
        #expect(!p.shares(nativeAmount: 20).contains { $0.userID == creator })
    }

    @Test("17: only the creator selected disables the button")
    func onlyCreator() {
        var p = people(count: 3)
        p.toggle(p.members[1])
        p.toggle(p.members[2])
        #expect(!p.isValid)
        #expect(p.summaryValue == "0 People, Including You")
        #expect(p.summarySecondLine == "You'll be marked as paid")
    }

    @Test("nobody selected reads Choose People")
    func nobodySelected() {
        var p = people(count: 3)
        for member in p.members where p.selected.contains(member) { p.toggle(member) }
        #expect(p.selected.isEmpty)
        #expect(p.summaryValue == "Choose People")
        #expect(p.summarySecondLine == nil)
    }

    @Test("18: checking a 101st share is refused and leaves the selection as it was")
    func hundredFirst() {
        var p = people(count: 101)
        #expect(p.summaryValue == "Choose People")
        for member in p.members.prefix(100) {
            let added = p.toggle(member)
            #expect(added)
        }
        let before = p.selected
        let overflow = p.toggle(p.members[100])
        #expect(!overflow)
        #expect(p.selected == before)
    }

    @Test("Groups of 100 or fewer start with everyone selected")
    func hundredStartsFull() {
        #expect(people(count: 100).selected.count == 100)
    }

    // MARK: - Widgets and details -

    @Test("19: a widget from another chat, or not from the creator, is unsupported")
    func widgetBelongs() {
        let r = request()
        #expect(r.belongs(to: chat, sentBy: creator))
        #expect(!r.belongs(to: .test(2), sentBy: creator))
        #expect(!r.belongs(to: chat, sentBy: UUID()))
        #expect(!r.belongs(to: chat, sentBy: nil))
    }

    private func details(_ r: GroupPaymentRequest, viewer: UserID, intent: Bool) -> PaymentRequestDetailsContent {
        PaymentRequestDetailsContent(request: r, title: "Dinner", viewer: viewer, hasPaymentIntent: intent, copy: copy, now: now) { _ in "Ada" }
    }

    @Test("20: no payment_intent_id for the viewer hides Send")
    func noIntentNoSend() throws {
        let r = request()
        let debtor = try #require(r.split?.shares[1].userID)
        #expect(details(r, viewer: debtor, intent: false).sendTitle == nil)
        #expect(details(r, viewer: debtor, intent: true).sendTitle == "Send $10")
    }

    @Test("Details rows: You, Paid, and the creator's mark-paid action only while OPEN")
    func detailsRows() throws {
        let open = details(request(paid: 2), viewer: creator, intent: false)
        #expect(open.requestedBy == "Requested by you")
        #expect(open.canClose)
        #expect(open.rows.map(\.name) == ["You", "Ada", "Ada", "Ada"])
        #expect(open.rows.map(\.status) == ["✓ Paid", "✓ Paid", "Hasn't paid yet", "Hasn't paid yet"])
        #expect(open.rows.map(\.action) == [.none, .none, .markPaid, .markPaid])

        let closed = details(request(paid: 2, status: .closed, closedAt: now), viewer: creator, intent: false)
        #expect(!closed.canClose)
        #expect(closed.rows.map(\.status) == ["✓ Paid", "✓ Paid", "Didn't pay", "Didn't pay"])
        #expect(closed.rows.allSatisfy { $0.action == .none })
    }
}

@Suite("Group payment requests: create copy")
@MainActor
struct PaymentRequestCreateCopyTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("The 4-week preset sits five minutes short of the server's limit")
    func fourWeeks() {
        #expect(PaymentRequestDeadline.fourWeeks.endsAt(sentAt: now) == now.addingTimeInterval(28 * 86_400 - 300))
        #expect(PaymentRequestDeadline.oneWeek.summaryValue() == "7 Days To Pay")
    }

    @Test("the custom picker runs from an hour out to five minutes short of 28 days")
    func customRange() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let range = PaymentRequestDeadline.customRange(openedAt: now)
        #expect(range.lowerBound == now.addingTimeInterval(60 * 60))
        #expect(range.upperBound == now.addingTimeInterval(28 * 24 * 60 * 60 - 5 * 60))
    }

    @Test("a custom deadline reads in medium date and short time, year included")
    func customSummary() throws {
        let locale = Locale(identifier: "en_US")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 18)))
        #expect(PaymentRequestDeadline.custom(date).summaryValue(locale: locale) == "Until Nov 2, 2026, 6:00\u{202F}PM")
    }

    @Test("The default title is the weekday followed by Request")
    func defaultTitle() {
        // 2027-01-15 08:00 UTC, a Friday from UTC−8 to UTC+15.
        let friday = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(defaultPaymentRequestTitle(at: friday, locale: Locale(identifier: "en_US")) == "Friday Request")
    }

    @Test("Titles are trimmed and limited to 100 scalars")
    func titleValidator() {
        let validator = PaymentRequestTitleValidator()
        #expect(validator.validate("  Dinner  ") == "Dinner")
        #expect(validator.validate("   ") == nil)
        #expect(validator.validate(String(repeating: "a", count: 100)) != nil)
        #expect(validator.validate(String(repeating: "a", count: 101)) == nil)
    }
}
