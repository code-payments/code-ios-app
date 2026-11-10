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

    private func deadline(endingIn seconds: TimeInterval) -> GroupPaymentRequest.Deadline {
        request(endsAt: now.addingTimeInterval(seconds)).deadline(at: now)
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
        #expect(GroupPaymentRequest.deckOrder([r], at: now).isEmpty)
    }

    // MARK: - Status line -

    @Test("4: 7 days left") func sevenDays() { #expect(status(endingIn: 7 * 86_400) == "7 days left to pay") }
    @Test("5: 6 d 1 h rounds up to 7 days") func sixDaysOneHour() { #expect(status(endingIn: 6 * 86_400 + 3_600) == "7 days left to pay") }
    @Test("6: 23 h 10 min reads 24 hours") func underADay() { #expect(status(endingIn: 23 * 3_600 + 600) == "24 hours left to pay") }
    @Test("22: exactly 24 hours reads in hours") func exactlyADay() { #expect(status(endingIn: 24 * 3_600) == "24 hours left to pay") }
    @Test("7: exactly 1 hour") func oneHour() { #expect(status(endingIn: 3_600) == "1 hour left to pay") }
    @Test("8: 30 s reads 1 minute") func thirtySeconds() { #expect(status(endingIn: 30) == "1 minute left to pay") }

    @Test("52: 7 d 59 s reads 7 days, not 8") func sevenDaysPlusSeconds() { #expect(deadline(endingIn: 7 * 86_400 + 59) == .daysLeft(7)) }
    @Test("53: 7 d 4 min still reads 7 days") func sevenDaysPlusFourMinutes() { #expect(deadline(endingIn: 7 * 86_400 + 4 * 60) == .daysLeft(7)) }
    @Test("54: 7 d 6 min reads 8 days") func sevenDaysPlusSixMinutes() { #expect(deadline(endingIn: 7 * 86_400 + 6 * 60) == .daysLeft(8)) }
    @Test("55: 24 h 30 s reads 24 hours") func dayPlusSeconds() { #expect(deadline(endingIn: 24 * 3_600 + 30) == .hoursLeft(24)) }
    @Test("56: 24 h 6 min reads 2 days") func dayPlusSixMinutes() { #expect(deadline(endingIn: 24 * 3_600 + 6 * 60) == .daysLeft(2)) }
    @Test("57: 1 h 2 min reads 1 hour") func hourPlusTwoMinutes() { #expect(deadline(endingIn: 3_600 + 2 * 60) == .hoursLeft(1)) }

    @Test("9: OPEN past its deadline reads as EXPIRED at ends_at")
    func pastDeadline() {
        let endsAt = now.addingTimeInterval(-1)
        let r = request(endsAt: endsAt)
        #expect(r.effectiveStatus(at: now) == .expired)
        #expect(r.effectiveClosedAt(at: now) == endsAt)
        #expect(PaymentRequestCopy.statusLine(r.deadline(at: now)) == "Expired")
        #expect(r.isEnded(at: now))
        #expect(GroupPaymentRequest.deckOrder([r], at: now).isEmpty)
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

    @Test("13: open by nearest deadline; ended requests are not in the deck")
    func deckOrder() {
        let twoDays = request(id: 1, endsAt: now.addingTimeInterval(2 * 86_400))
        let fiveDays = request(id: 2, endsAt: now.addingTimeInterval(5 * 86_400))
        let closed = request(id: 3, status: .closed, closedAt: now.addingTimeInterval(-3 * 3_600))
        let expired = request(id: 4, status: .expired, endsAt: now.addingTimeInterval(-30 * 3_600), closedAt: now.addingTimeInterval(-30 * 3_600))

        let deck = GroupPaymentRequest.deckOrder([closed, expired, fiveDays, twoDays], at: now)

        #expect(deck.map(\.id) == [twoDays.id, fiveDays.id])
    }

    private func emptyStore() -> PaymentRequests {
        PaymentRequests(getChatPage: { _, _, _ in [] }, getRequest: { _ in throw ErrorGetPaymentRequest.unknown })
    }

    private func deckItems(_ store: PaymentRequests, at now: Date) -> [PaymentRequestDeckItem] {
        store.deckItems(for: chat, viewer: viewer, order: PaymentRequestDeckOrder(), copy: copy, now: now)
    }

    private func timelineStatus(_ store: PaymentRequests, _ id: PaymentRequestID) -> String? {
        guard case .card(let card) = store.cardState(for: id, in: chat, sentBy: creator, copy: copy, now: now) else { return nil }
        return card.statusLine
    }

    @Test("58: the last unpaid share is paid, so the request leaves the deck and the deck fades out")
    func completingLeavesDeck() async throws {
        let store = emptyStore()
        store.ingest([request(id: 1, paid: 3)])
        let before = deckItems(store, at: now)
        #expect(before.count == 1)

        let presence = PaymentRequestDeckPresence()
        presence.update(before, completed: { _ in nil }, animates: true)
        #expect(presence.isVisible)

        store.ingest([request(id: 1, paid: 4, status: .completed, closedAt: now, version: 2)])
        let after = deckItems(store, at: now)
        #expect(after.isEmpty)
        #expect(timelineStatus(store, before[0].id) == "Paid in full")

        // The completed card stays, its ring swept to full, before the deck fades out.
        let completed = store.completedDeckItem(before[0].id, viewer: viewer, copy: copy, now: now)
        #expect(completed?.card.fraction == 1)
        presence.update(after, completed: { store.completedDeckItem($0, viewer: viewer, copy: copy, now: now) }, animates: true)
        #expect(presence.held?.map(\.card.fraction) == [1])
        #expect(presence.isVisible)

        // Polled: the sweep's clock starts when its task first gets the main actor, which other
        // suites in the same process can hold well past any fixed margin.
        try await waitUntil(presence) { $0.held == nil }
        #expect(!presence.isVisible)
    }

    @Test("58: under Reduce Motion the completed request leaves at once")
    func completingLeavesWithoutMotion() {
        let store = emptyStore()
        store.ingest([request(id: 1, paid: 3)])
        let presence = PaymentRequestDeckPresence()
        presence.update(deckItems(store, at: now), completed: { _ in nil }, animates: true)
        store.ingest([request(id: 1, paid: 4, status: .completed, closedAt: now, version: 2)])
        presence.update(deckItems(store, at: now), completed: { store.completedDeckItem($0, viewer: viewer, copy: copy, now: now) }, animates: false)
        #expect(presence.held == nil)
        #expect(!presence.isVisible)
    }

    @Test("58: a closed or expired request leaves without holding its place")
    func closedLeavesWithoutSweep() throws {
        let store = emptyStore()
        store.ingest([request(id: 1), request(id: 2, endsAt: now.addingTimeInterval(86_400))])
        let previous = deckItems(store, at: now)
        let live = Array(previous.dropFirst())
        let held = try #require(PaymentRequestDeckPresence.holding(previous: previous, live: live, completed: { _ in nil }))
        #expect(!held.sweeps)
        #expect(held.items.map(\.id) == previous.map(\.id))
        #expect(PaymentRequestDeckPresence.holding(previous: live, live: live, completed: { _ in nil }) == nil)
    }

    @Test("59: of OPEN, COMPLETED, CLOSED and EXPIRED, only the OPEN one is in the deck")
    func onlyOpenInDeck() {
        let store = emptyStore()
        let open = request(id: 1)
        let completed = request(id: 2, paid: 4, status: .completed, closedAt: now.addingTimeInterval(-3_600))
        let closed = request(id: 3, status: .closed, closedAt: now.addingTimeInterval(-3_600))
        let expired = request(id: 4, status: .expired, endsAt: now.addingTimeInterval(-3_600), closedAt: now.addingTimeInterval(-3_600))
        store.ingest([open, completed, closed, expired])

        #expect(deckItems(store, at: now).map(\.id) == [open.id])
        #expect(timelineStatus(store, completed.id) == "Paid in full")
        #expect(timelineStatus(store, closed.id) != nil)
        #expect(timelineStatus(store, expired.id) == "Expired")
    }

    @Test("60: the front card leaves at its ends_at and the other comes to the front")
    func frontExpiresOnScreen() {
        let store = emptyStore()
        let endsAt = now.addingTimeInterval(90)
        let front = request(id: 1, endsAt: endsAt)
        let back = request(id: 2, endsAt: now.addingTimeInterval(86_400))
        store.ingest([front, back])

        #expect(deckItems(store, at: now).map(\.id) == [front.id, back.id])
        // The deck wakes at ends_at itself, not at the next minute's refresh.
        #expect(GroupPaymentRequest.nextExpiry(of: [front, back], after: now) == endsAt)
        #expect(deckItems(store, at: endsAt.addingTimeInterval(-1)).map(\.id) == [front.id, back.id])
        #expect(deckItems(store, at: endsAt).map(\.id) == [back.id])
        #expect(GroupPaymentRequest.nextExpiry(of: [back], after: endsAt) == back.split?.endsAt)
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

    @Test("24–25: every viewer gets the stack, and only a viewer who owes gets You owe and Pay")
    @MainActor
    func stackForEveryViewer() {
        let store = PaymentRequests(getChatPage: { _, _, _ in [] }, getRequest: { _ in throw ErrorGetPaymentRequest.unknown })
        store.ingest([request(id: 1, paid: 1)])
        func front(for viewer: UUID) -> PaymentRequestDeckItem? {
            store.deckItems(for: chat, viewer: viewer, order: PaymentRequestDeckOrder(), copy: copy, now: now).first
        }

        let owing = front(for: viewer)
        #expect(owing?.owedShare != nil)
        if case .owes = owing?.viewerStatus {} else { Issue.record("expected .owes, got \(String(describing: owing?.viewerStatus))") }

        let asCreator = front(for: creator)
        #expect(asCreator != nil)
        #expect(asCreator?.owedShare == nil)
        #expect(asCreator?.viewerStatus == .creator)

        let outsider = front(for: UUID())
        #expect(outsider != nil)
        #expect(outsider?.owedShare == nil)
        #expect(outsider?.viewerStatus == .noShare)

        store.ingest([request(id: 1, paid: 2, version: 2)])
        let paid = front(for: viewer)
        #expect(paid != nil)
        #expect(paid?.owedShare == nil)
        if case .paid = paid?.viewerStatus {} else { Issue.record("expected .paid, got \(String(describing: paid?.viewerStatus))") }
    }

    @Test("27: dragging the stack up only pulls the front card a few points")
    @MainActor
    func upwardDragIsElastic() {
        let cap = PaymentRequestStack.maxUpwardPull

        #expect(PaymentRequestStack.upwardPull(40) == 0)
        #expect(PaymentRequestStack.upwardPull(0) == 0)
        let short = PaymentRequestStack.upwardPull(-10)
        let long = PaymentRequestStack.upwardPull(-400)
        #expect(short < 0 && short > -10)
        #expect(long < short)
        #expect(long > -cap)
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

    @Test("14: $20 per person, everyone selected in a 26-member group")
    func everyone() {
        let p = people(count: 26)
        #expect(p.summaryValue == "Everyone, Including You")
        #expect(p.summarySecondLine == "You'll be marked as paid")
        #expect(paymentRequestSendButtonTitle == "Send Request")
        let shares = p.shares(perPerson: .usd(20))
        #expect(shares.count == 26)
        #expect(shares.first?.userID == creator)
        #expect(shares.allSatisfy { !$0.isPaid && $0.nativeAmount == 20 })
    }

    @Test("15: $20 per person, the creator and one other")
    func creatorAndOne() {
        var p = people(count: 3)
        p.toggle(p.members[2])
        #expect(p.summaryValue == "1 Person, Including You")
        #expect(paymentRequestSendButtonTitle == "Send Request")
        #expect(p.shares(perPerson: .usd(20)).map(\.nativeAmount) == [20, 20])
    }

    @Test("16: everyone except the creator")
    func everyoneExceptYou() {
        var p = people(count: 5)
        p.toggle(creator)
        #expect(p.summaryValue == "Everyone Except You")
        #expect(p.summarySecondLine == nil)
        #expect(p.shares(perPerson: .usd(20)).contains { $0.userID == creator } == false)
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

    // MARK: - Amount per person -

    @Test("49: $33.33 per person, the creator and two others")
    func perPersonWithCreator() {
        let p = people(count: 3)
        let amount = FiatAmount.usd(Decimal(string: "33.33")!)
        let shares = p.shares(perPerson: amount)
        #expect(shares.map(\.nativeAmount) == [33.33, 33.33, 33.33])
        #expect(shares.compactMap(\.userID) == p.members)
        #expect(paymentRequestSendButtonTitle == "Send Request")
    }

    @Test("50: $20 per person, the creator deselected, one other")
    func perPersonToOne() {
        var p = people(count: 3)
        p.toggle(creator)
        p.toggle(p.members[2])
        #expect(p.shares(perPerson: .usd(20)).map(\.nativeAmount) == [20])
        #expect(paymentRequestSendButtonTitle == "Send Request")
    }

    @Test("51: unchecking the creator in a 26-member group keeps Send Request and drops a share")
    func uncheckingCreator() {
        var p = people(count: 26)
        #expect(paymentRequestSendButtonTitle == "Send Request")
        p.toggle(creator)
        #expect(paymentRequestSendButtonTitle == "Send Request")
        let shares = p.shares(perPerson: .usd(20))
        #expect(shares.count == 25)
        #expect(shares.allSatisfy { $0.nativeAmount == 20 })
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

    @Test("61: the Name screen opens empty over the weekday default, and back keeps it")
    func nameScreenDefault() {
        // 2027-01-18 08:00 UTC, a Monday from UTC−8 to UTC+15.
        let monday = Date(timeIntervalSince1970: 1_800_000_000 + 3 * 86_400)
        let name = PaymentRequestName(defaultTitle: defaultPaymentRequestTitle(at: monday, locale: Locale(identifier: "en_US")))
        #expect(name.fieldText.isEmpty)
        #expect(name.placeholder == "Monday Request")
        // Done is disabled while the field is empty.
        #expect(PaymentRequestTitleValidator().validate(name.fieldText) == nil)
        // Going back without Done saves nothing, so the default stands.
        #expect(name.title == "Monday Request")
    }

    @Test("62: the Name screen opened after saving Rent reads Rent")
    func nameScreenSaved() {
        var name = PaymentRequestName(defaultTitle: "Monday Request")
        name.save("Rent")
        #expect(name.fieldText == "Rent")
        #expect(name.title == "Rent")
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
