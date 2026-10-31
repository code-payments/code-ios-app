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

    @Test("26: viewer owes and scrolls away, so the strip shrinks into the pill")
    func stripShrinksWhenScrolledAway() {
        #expect(PaymentRequestDeckStyle.collapsed(owes: true, isScrolledAway: false) == .strip)
        #expect(PaymentRequestDeckStyle.collapsed(owes: true, isScrolledAway: true) == .pill)
        #expect(PaymentRequestDeckStyle.collapsed(owes: false, isScrolledAway: false) == .pill)
    }

    @Test("26: the strip shrinks in step with the scroll, not at a single point")
    @MainActor
    func stripTracksScroll() {
        let collapse = PaymentRequestStripCollapse()
        let distance = PaymentRequestStripCollapse.distance

        collapse.update(distanceFromNewest: distance / 4)
        #expect(collapse.progress == 0.25)
        collapse.update(distanceFromNewest: distance / 2)
        #expect(collapse.progress == 0.5)
        collapse.update(distanceFromNewest: -20)
        #expect(collapse.progress == 0)
        #expect(!collapse.isPinned)
    }

    @Test("26: once fully shrunk, scrolling back to the newest messages leaves the strip in the pill")
    @MainActor
    func stripStaysPinned() {
        let collapse = PaymentRequestStripCollapse()
        let distance = PaymentRequestStripCollapse.distance

        collapse.update(distanceFromNewest: distance * 3)
        #expect(collapse.isPinned)
        collapse.update(distanceFromNewest: 0)
        #expect(collapse.progress == 1)
        #expect(collapse.isScrolledAway)
    }

    @Test("27: reopening the chat while still owing shows the strip again")
    @MainActor
    func reopenShowsStrip() {
        let pinned = PaymentRequestStripCollapse()
        pinned.update(distanceFromNewest: PaymentRequestStripCollapse.distance)
        #expect(pinned.isPinned)

        // A visit owns its collapse, so a reopened chat starts from a fresh one.
        let reopened = PaymentRequestStripCollapse()
        #expect(reopened.progress == 0)
        #expect(!reopened.isScrolledAway)
    }

    @Test("28: a new owed request while the chat is open brings the strip back")
    @MainActor
    func newOwedRequestUnpins() {
        let collapse = PaymentRequestStripCollapse()
        collapse.update(distanceFromNewest: PaymentRequestStripCollapse.distance)
        collapse.unpin()
        #expect(!collapse.isPinned)
        #expect(!collapse.isScrolledAway)
        #expect(collapse.progress == 0)
        collapse.update(distanceFromNewest: PaymentRequestStripCollapse.distance / 2)
        #expect(collapse.progress == 0.5)
    }

    @Test("26: a small scroll back and forth past the middle never flaps the style")
    @MainActor
    func stripStyleHasHysteresis() {
        let collapse = PaymentRequestStripCollapse()
        let distance = PaymentRequestStripCollapse.distance

        collapse.update(distanceFromNewest: distance * 0.55)
        #expect(!collapse.isScrolledAway)
        collapse.update(distanceFromNewest: distance * 0.7)
        #expect(collapse.isScrolledAway)
        collapse.update(distanceFromNewest: distance * 0.45)
        #expect(collapse.isScrolledAway)
        collapse.update(distanceFromNewest: distance * 0.3)
        #expect(!collapse.isScrolledAway)
    }

    // MARK: - Viewer status -

    /// A $45 request in $5 shares: the creator's, the viewer's, then seven others, `othersPaid` of
    /// them paid.
    private func ninePeople(viewerPaid: Bool, othersPaid: Int, version: UInt64 = 1) -> GroupPaymentRequest {
        let others = (0..<7).map { index in
            GroupPaymentRequest.Share(userID: UUID(), nativeAmount: 5, settlement: index < othersPaid ? .manual : nil)
        }
        let shares = [
            GroupPaymentRequest.Share(userID: creator, nativeAmount: 5, settlement: .creator),
            GroupPaymentRequest.Share(userID: viewer, nativeAmount: 5, settlement: viewerPaid ? .manual : nil),
        ] + others
        return GroupPaymentRequest(
            id: PaymentRequestID(data: Data([9])),
            creator: creator,
            createdAt: now.addingTimeInterval(-60),
            status: .open,
            closedAt: nil,
            version: version,
            chatID: chat,
            split: .init(
                text: .plaintext(title: "Dinner", description: ""),
                currency: "usd",
                endsAt: now.addingTimeInterval(7 * 24 * 3600),
                shares: shares
            )
        )
    }

    private func line(_ status: PaymentRequestViewerStatus, _ request: GroupPaymentRequest) -> String {
        String(status.line(amounts: copy.deckAmounts(request)).characters)
    }

    @Test("29: viewer paid their $5 share of a request at $15 of $45")
    func viewerPaid() {
        let r = ninePeople(viewerPaid: true, othersPaid: 1)
        let status = PaymentRequestViewerStatus(request: r, viewer: viewer, copy: copy)
        #expect(status.showsPaidBadge)
        #expect(line(status, r) == "✓ You paid $5 · $15 of $45")
        #expect(status.lead.map { String($0.characters) } == "✓ You paid $5")
        #expect(
            copy.deckAccessibilityLabel(front: r, title: "Dinner", viewerStatus: status, count: 1, now: now)
                == "Dinner, you paid $5, $15 of $45 paid, 7 days left to pay"
        )
    }

    @Test("30: viewer owes $5 on a request at $10 of $45")
    func viewerOwes() {
        let r = ninePeople(viewerPaid: false, othersPaid: 1)
        let status = PaymentRequestViewerStatus(request: r, viewer: viewer, copy: copy)
        #expect(!status.showsPaidBadge)
        #expect(line(status, r) == "You owe $5 · $10 of $45")
    }

    @Test("31: viewer created the request")
    func viewerCreated() {
        let r = ninePeople(viewerPaid: true, othersPaid: 1)
        let status = PaymentRequestViewerStatus(request: r, viewer: creator, copy: copy)
        #expect(!status.showsPaidBadge)
        #expect(line(status, r) == "Your request · $15 of $45")
    }

    @Test("32: viewer has no share")
    func viewerHasNoShare() {
        let r = ninePeople(viewerPaid: true, othersPaid: 1)
        let status = PaymentRequestViewerStatus(request: r, viewer: UUID(), copy: copy)
        #expect(!status.showsPaidBadge)
        #expect(line(status, r) == "$15 of $45")
        #expect(
            copy.deckAccessibilityLabel(front: r, title: "Dinner", viewerStatus: status, count: 2, now: now)
                == "2 requests, Dinner, $15 of $45 paid, 7 days left to pay"
        )
    }

    @Test("33: the creator marks the viewer's share paid, and the refetched request shows it")
    func markedPaidAfterRefetch() {
        let before = ninePeople(viewerPaid: false, othersPaid: 1)
        let after = GroupPaymentRequest.merged(existing: before, incoming: ninePeople(viewerPaid: true, othersPaid: 1, version: 2))
        #expect(!PaymentRequestViewerStatus(request: before, viewer: viewer, copy: copy).showsPaidBadge)
        let status = PaymentRequestViewerStatus(request: after, viewer: viewer, copy: copy)
        #expect(status.showsPaidBadge)
        #expect(line(status, after) == "✓ You paid $5 · $15 of $45")
    }

    // MARK: - People -

    private func people(count: Int) -> PaymentRequestPeople {
        PaymentRequestPeople(members: [creator] + (1..<count).map { _ in UUID() }, creator: creator)
    }

    @Test("14: a $520 total, everyone selected in a 26-member group")
    func everyone() throws {
        let p = people(count: 26)
        #expect(p.summaryValue == "Everyone, Including You")
        #expect(p.summarySecondLine == "You'll be marked as paid")
        #expect(p.buttonTitle(total: .usd(520)) == "Request $20 Each")
        let shares = try #require(p.shares(total: .usd(520)))
        #expect(shares.count == 26)
        #expect(shares.first?.userID == creator)
        #expect(shares.allSatisfy { !$0.isPaid && $0.nativeAmount == 20 })
    }

    @Test("15: a $40 total, the creator and one other")
    func creatorAndOne() {
        var p = people(count: 3)
        p.toggle(p.members[2])
        #expect(p.summaryValue == "1 Person, Including You")
        #expect(p.buttonTitle(total: .usd(40)) == "Request $20 Each")
        #expect(p.shareAmounts(total: .usd(40)) == [.usd(20), .usd(20)])
    }

    @Test("16: everyone except the creator")
    func everyoneExceptYou() {
        var p = people(count: 5)
        p.toggle(creator)
        #expect(p.summaryValue == "Everyone Except You")
        #expect(p.summarySecondLine == nil)
        #expect(p.shares(total: .usd(20))?.contains { $0.userID == creator } == false)
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

    // MARK: - Splitting the total -

    @Test("49: $100 between the creator and two others puts the extra cent on the first other")
    func splitWithCreator() {
        var p = people(count: 4)
        p.toggle(p.members[3])
        #expect(p.shareAmounts(total: .usd(100)) == [.usd(Decimal(string: "33.33")!), .usd(Decimal(string: "33.34")!), .usd(Decimal(string: "33.33")!)])
        #expect(p.shares(total: .usd(100))?.compactMap(\.userID) == Array(p.members.prefix(3)))
        #expect(p.buttonTitle(total: .usd(100)) == "Request ~$33.33 Each")
    }

    @Test("53: $100.02 between the creator and two others splits evenly, with no ~")
    func splitEvenWithCreator() {
        let p = people(count: 3)
        let total = FiatAmount.usd(Decimal(string: "100.02")!)
        #expect(p.shareAmounts(total: total) == Array(repeating: .usd(Decimal(string: "33.34")!), count: 3))
        #expect(p.buttonTitle(total: total) == "Request $33.34 Each")
    }

    @Test("50: $100.02 between three others, the creator deselected, splits evenly")
    func splitWithoutCreator() throws {
        var p = people(count: 4)
        p.toggle(creator)
        let total = FiatAmount.usd(Decimal(string: "100.02")!)
        let amounts = try #require(p.shareAmounts(total: total))
        #expect(amounts == Array(repeating: .usd(Decimal(string: "33.34")!), count: 3))
        #expect(amounts.reduce(.zero(in: .usd), +) == total)
    }

    @Test("51: $0.02 between the creator and two others can't be split")
    func splitTooSmall() {
        let p = people(count: 3)
        let total = FiatAmount.usd(Decimal(string: "0.02")!)
        #expect(p.shares(total: total) == nil)
        #expect(p.buttonTitle(total: total) == nil)
    }

    @Test("52: $40 to one other, the creator deselected, is one $40 share")
    func splitToOne() {
        var p = people(count: 3)
        p.toggle(creator)
        p.toggle(p.members[2])
        #expect(p.shareAmounts(total: .usd(40)) == [.usd(40)])
        #expect(p.buttonTitle(total: .usd(40)) == "Request $40 Each")
    }

    @Test("The remainder never reaches the creator, and the shares always sum to the total",
          arguments: [(3, 2), (5, 3), (101, 7), (9_999, 100), (100, 100)])
    func splitSums(total: Int, count: Int) throws {
        let units = try #require(PaymentRequestPeople.splitUnits(total: total, count: count, creatorIndex: 0))
        #expect(units.reduce(0, +) == total)
        #expect(units[0] == total / count)
        #expect(units.max()! - units.min()! <= 1)
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
        #expect(details(r, viewer: debtor, intent: false).payTitle == nil)
        #expect(details(r, viewer: debtor, intent: true).payTitle == "Pay $10")
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

@Suite("Group payment requests: Time To Pay sheet")
@MainActor
struct PaymentRequestDeadlinePickerTests {

    private let locale = Locale(identifier: "en_US")
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        // A fixed offset, so the spec's wall-clock times hold across the November DST change.
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1
        return calendar
    }()

    private func date(_ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func picker(_ deadline: PaymentRequestDeadline = .oneWeek, openedAt now: Date) -> PaymentRequestDeadlinePicker {
        PaymentRequestDeadlinePicker(deadline: deadline, now: now, calendar: calendar, locale: locale)
    }

    @Test("34: the grid starts on the locale's first weekday and enables today through today + 28 days")
    func grid() {
        let picker = picker(openedAt: date(10, 26, 11, 39))
        #expect(picker.gridDays.count == 35)
        #expect(picker.gridDays.first == date(10, 25))
        #expect(!picker.isEnabled(date(10, 25)))
        #expect(picker.isEnabled(date(10, 26)))
        #expect(picker.isEnabled(date(11, 23)))
        #expect(!picker.isEnabled(date(11, 24)))
        #expect(picker.selectedPreset == .oneWeek)
        #expect(picker.selectedDay == date(11, 2))
        #expect(picker.customDate == nil)
        #expect(picker.rangeStart == date(10, 26))
        #expect(picker.band(for: date(10, 25)) == nil)
        #expect(picker.band(for: date(10, 26)) == RangeBand(fromCenter: true, toCenter: false, roundedLeading: false, roundedTrailing: false))
        #expect(picker.band(for: date(10, 28)) == RangeBand(fromCenter: false, toCenter: false, roundedLeading: false, roundedTrailing: false))
        #expect(picker.band(for: date(10, 31)) == RangeBand(fromCenter: false, toCenter: false, roundedLeading: false, roundedTrailing: true))
        #expect(picker.band(for: date(11, 1)) == RangeBand(fromCenter: false, toCenter: false, roundedLeading: true, roundedTrailing: false))
        #expect(picker.band(for: date(11, 2)) == RangeBand(fromCenter: false, toCenter: true, roundedLeading: false, roundedTrailing: false))
        #expect(picker.band(for: date(11, 3)) == nil)
        #expect(picker.closesValue == "≈ Mon, Nov 2")
        #expect(picker.summaryLine == "1 Week · closes 7 days after you send")
        #expect(picker.timeText(picker.timeRowDate) == "11:39\u{202F}AM")
    }

    @Test("35: tapping a day makes it custom at 6:00 PM")
    func customDay() throws {
        let picker = picker(openedAt: date(10, 26, 11, 39))
        picker.select(day: date(11, 5))
        #expect(picker.selectedPreset == nil)
        let custom = try #require(picker.customDate)
        #expect(custom == date(11, 5, 18))
        #expect(picker.timeText(custom) == "6:00\u{202F}PM")
        #expect(picker.closesValue == "Thu, Nov 5, 6:00\u{202F}PM")
        #expect(picker.summaryLine == "Custom · 10 days")
        #expect(picker.band(for: date(11, 5))?.toCenter == true)
        #expect(picker.band(for: date(11, 6)) == nil)
    }

    @Test("36: today's default time moves up to an hour from now")
    func clampToday() {
        let picker = picker(openedAt: date(10, 26, 17, 30))
        picker.select(day: date(10, 26))
        #expect(picker.customDate == date(10, 26, 18, 30))
    }

    @Test("37: the last day's default time moves down to 28 days less five minutes from now")
    func clampLastDay() {
        let picker = picker(openedAt: date(10, 26, 11, 39))
        picker.select(day: date(11, 23))
        #expect(picker.customDate == date(11, 23, 11, 34))
    }

    @Test("38: a chip after a custom day clears the custom date and highlights its day")
    func chipAfterCustom() {
        let picker = picker(openedAt: date(10, 26, 11, 39))
        picker.select(day: date(11, 5))
        picker.select(.twoWeeks)
        #expect(picker.customDate == nil)
        #expect(picker.selectedDay == date(11, 9))
        #expect(picker.band(for: date(11, 9))?.toCenter == true)
        #expect(picker.summaryLine == "2 Weeks · closes 14 days after you send")
        #expect(picker.timeRowDate == date(11, 9, 11, 39))
    }

    @Test("41: changing a preset's time makes its closing day custom at that time")
    func presetTime() {
        let picker = picker(openedAt: date(10, 26, 11, 39))
        picker.setTime(date(10, 26, 15))
        #expect(picker.selectedPreset == nil)
        #expect(picker.customDate == date(11, 2, 15))
        #expect(picker.closesValue == "Mon, Nov 2, 3:00\u{202F}PM")
        #expect(picker.summaryLine == "Custom · 7 days")
        #expect(picker.choice == .custom(date(11, 2, 15)))
    }

    @Test("42: a time past 4 Weeks moves down to 28 days less five minutes from now")
    func presetTimeClamp() {
        let picker = picker(openedAt: date(10, 26, 11, 39))
        picker.select(.fourWeeks)
        picker.setTime(date(10, 26, 11, 50))
        #expect(picker.selectedPreset == nil)
        #expect(picker.customDate == date(11, 23, 11, 34))
        #expect(picker.selectedDay == date(11, 23))
    }

    @Test("45: tapping a day after changing the time keeps that time")
    func dayKeepsTime() {
        let picker = picker(openedAt: date(10, 26, 11, 39))
        picker.setTime(date(10, 26, 15))
        picker.select(day: date(11, 5))
        #expect(picker.customDate == date(11, 5, 15))
        #expect(picker.closesValue == "Thu, Nov 5, 3:00\u{202F}PM")
    }

    @Test("48: the band runs square up to the start and end circles")
    func squareEnds() {
        let picker = picker(openedAt: date(10, 26, 11, 39))
        let start = picker.band(for: date(10, 26))
        let end = picker.band(for: date(11, 2))
        #expect(start?.fromCenter == true)
        #expect(start?.roundedLeading == false)
        #expect(end?.toCenter == true)
        #expect(end?.roundedTrailing == false)
    }

    @Test("39: the summary keeps its choice until Done, and reopening shows the current one")
    func dismissKeepsChoice() {
        let deadline = PaymentRequestDeadline.oneWeek
        let picker = picker(deadline, openedAt: date(10, 26, 11, 39))
        picker.select(day: date(11, 5))
        #expect(deadline.summaryValue() == "7 Days To Pay")

        let reopened = self.picker(picker.choice, openedAt: date(10, 26, 11, 45))
        #expect(reopened.customDate == date(11, 5, 18))
        reopened.select(day: date(11, 7))
        #expect(reopened.customDate == date(11, 7, 18))
    }

    @Test("40: today tapped shows only the closing circle, with no band")
    func closesToday() {
        let picker = picker(openedAt: date(10, 26, 11, 39))
        picker.select(day: date(10, 26))
        #expect(picker.selectedDay == date(10, 26))
        #expect(picker.rangeStart == nil)
        #expect(picker.band(for: date(10, 26)) == nil)
        #expect(picker.closesValue == "Mon, Oct 26, 6:00\u{202F}PM")
    }
}
