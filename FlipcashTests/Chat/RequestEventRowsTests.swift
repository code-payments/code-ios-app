//
//  RequestEventRowsTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
import FlipcashStore
@testable import Flipcash

// MARK: - Fixtures -

private let alex = UserID()
private let jordan = UserID()
private let sam = UserID()
private let chat = ConversationID.test(7)
private let tahoe = PaymentRequestID(data: Data([1]))
private let names: [UserID: String] = [alex: "Alex", jordan: "Jordan", sam: "Sam"]

/// A fixed local noon, so a fixture's offsets stay inside one day unless a test crosses midnight.
private let noon: Date = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12))!

private func dollars(_ value: Decimal) -> ExchangedFiat {
    ExchangedFiat(
        onChainAmount: TokenAmount(quarks: UInt64(truncating: (value * 1_000_000) as NSDecimalNumber), mint: .usdf),
        nativeAmount: FiatAmount(value: value, currency: .usd),
        currencyRate: Rate(fx: 1, currency: .usd)
    )
}

/// A share of `request` paid by `payer` to `creator`, `minutes` after noon.
private func payment(
    _ id: UInt64,
    by payer: UserID,
    to creator: UserID? = alex,
    _ amount: Decimal = 40,
    for request: PaymentRequestID? = tahoe,
    minutes: Double? = nil
) -> ConversationMessage {
    ConversationMessage(
        id: MessageID(value: id),
        senderID: payer,
        content: .cash(dollars(amount)),
        cashReceiverID: creator,
        paymentRequestID: request,
        date: noon.addingTimeInterval((minutes ?? Double(id)) * 60),
        unreadSeq: id
    )
}

private func text(_ id: UInt64, from sender: UserID, minutes: Double? = nil) -> ConversationMessage {
    ConversationMessage(
        id: MessageID(value: id),
        senderID: sender,
        content: .text("m\(id)"),
        date: noon.addingTimeInterval((minutes ?? Double(id)) * 60),
        unreadSeq: id
    )
}

private typealias Share = GroupPaymentRequest.Share

/// A request by Alex titled `title`, with the creator's own share paid at creation.
private func request(
    _ id: PaymentRequestID = tahoe,
    title: String = "Tahoe cabin",
    shares: [Share],
    status: GroupPaymentRequest.Status = .open,
    closedAt: Date? = nil
) -> RequestTimeline {
    RequestTimeline(
        request: GroupPaymentRequest(
            id: id,
            creator: alex,
            createdAt: noon.addingTimeInterval(-3600),
            status: status,
            closedAt: closedAt,
            version: 1,
            chatID: chat,
            split: .init(text: .plaintext(title: title, description: ""), currency: "usd", endsAt: nil, shares: shares)
        ),
        title: title
    )
}

private func creatorShare(_ amount: Double = 10) -> Share {
    Share(userID: alex, nativeAmount: amount, paidAt: noon.addingTimeInterval(-3600), settlement: .creator)
}

private func paid(_ user: UserID, _ amount: Double = 10, minutes: Double) -> Share {
    Share(userID: user, nativeAmount: amount, paidAt: noon.addingTimeInterval(minutes * 60), settlement: .intent(Data([1])))
}

private func marked(_ user: UserID, _ amount: Double = 10, minutes: Double) -> Share {
    Share(userID: user, nativeAmount: amount, paidAt: noon.addingTimeInterval(minutes * 60), settlement: .manual)
}

private func owed(_ user: UserID, _ amount: Double = 10) -> Share {
    Share(userID: user, nativeAmount: amount)
}

private func rows(
    _ messages: [ConversationMessage],
    viewer: UserID,
    requests: [RequestTimeline] = [],
    extraNames: [UserID: String] = [:]
) -> [ChatRequestEvent] {
    items(messages, viewer: viewer, requests: requests, extraNames: extraNames).compactMap {
        if case .requestEvent(let event) = $0 { event } else { nil }
    }
}

private func items(
    _ messages: [ConversationMessage],
    viewer: UserID,
    requests: [RequestTimeline] = [],
    extraNames: [UserID: String] = [:]
) -> [ChatItem] {
    ChatItem.from(
        messages,
        selfUserID: viewer,
        nameOf: { names[$0] ?? extraNames[$0] },
        requests: Dictionary(uniqueKeysWithValues: requests.map { ($0.request.id, $0) })
    )
}

private func line(_ event: ChatRequestEvent) -> String { event.spokenText }

/// The semibold parts of a row's caption.
private func emphasized(_ event: ChatRequestEvent) -> [String] {
    event.caption.filter(\.isEmphasized).map(\.text)
}

// MARK: - Share payment rows -

@Suite("Share payment rows (spec cases 63-74)")
struct SharePaymentRowTests {

    private var tahoeCabin: RequestTimeline {
        request(shares: [creatorShare(40), paid(jordan, 40, minutes: 1), owed(sam, 40)])
    }

    @Test("63: the row reads per viewer", arguments: [
        (jordan, "You paid $40 · Tahoe cabin", ["You"]),
        (alex, "Jordan paid you $40 · Tahoe cabin", ["Jordan", "you"]),
        (sam, "Jordan paid Alex $40 · Tahoe cabin", ["Jordan", "Alex"]),
    ])
    func copyPerViewer(viewer: UserID, expected: String, semibold: [String]) throws {
        let row = try #require(rows([payment(1, by: jordan)], viewer: viewer, requests: [tahoeCabin]).first)
        #expect(line(row) == expected)
        #expect(emphasized(row) == semibold)
        #expect(row.kind == .sharePayment)
        #expect(row.amount == "$40")
        #expect(row.requestID == tahoe.data)
    }

    @Test("63: a payment that names no receiver, for a request not stored, reads without one")
    func noReceiver() throws {
        let row = try #require(rows([payment(1, by: jordan, to: nil)], viewer: sam, requests: []).first)
        #expect(line(row) == "Jordan paid $40")
    }

    @Test("63: a share payment draws no cash bubble")
    func replacesTheCashBubble() {
        let drawn = items([payment(1, by: jordan)], viewer: sam, requests: [tahoeCabin])
        #expect(!drawn.contains { if case .message = $0 { true } else { false } })
    }

    @Test("64: each row's ring is the paid fraction as of that payment")
    func ringAsOfPayment() {
        let b = UserID(), c = UserID(), d = UserID()
        let four = request(shares: [creatorShare(), paid(b, minutes: 1), paid(c, minutes: 3), owed(d)])
        // A text between them keeps the two payments from collapsing.
        let drawn = rows([payment(1, by: b, 10), text(2, from: sam), payment(3, by: c, 10)], viewer: sam, requests: [four])
        #expect(drawn.map(\.ringFraction) == [0.5, 0.75])
    }

    @Test("65: a later mark leaves earlier rings alone")
    func laterMarkLeavesRings() {
        let b = UserID(), c = UserID(), d = UserID()
        let four = request(shares: [creatorShare(), paid(b, minutes: 1), paid(c, minutes: 3), marked(d, minutes: 5)])
        let drawn = rows([payment(1, by: b, 10), text(2, from: sam), payment(3, by: c, 10)], viewer: sam, requests: [four])
        #expect(drawn.filter { $0.kind == .sharePayment }.map(\.ringFraction) == [0.5, 0.75])
    }

    @Test("64: a payment the stored request doesn't show yet still counts itself")
    func ringCountsOwnPaymentBeforeRefetch() throws {
        let b = UserID()
        let stale = request(shares: [creatorShare(), owed(b), owed(sam), owed(jordan)])
        let row = try #require(rows([payment(1, by: b, 10)], viewer: sam, requests: [stale]).first)
        #expect(row.ringFraction == 0.5)
    }

    @Test("66: a run for one request collapses; a message between ends the run")
    func collapsesARun() {
        let b = UserID(), c = UserID(), d = UserID(), e = UserID()
        let five = request(title: "Pizza", shares: [creatorShare(), paid(b, minutes: 1), paid(c, minutes: 2), paid(d, minutes: 3), paid(e, minutes: 5)])
        let drawn = rows(
            [payment(1, by: b, 10), payment(2, by: c, 10), payment(3, by: d, 10), text(4, from: sam), payment(5, by: e, 10)],
            viewer: sam, requests: [five], extraNames: [e: "Eve"]
        )
        #expect(drawn.map(line) == ["3 people paid $30 · Pizza", "Eve paid Alex $10 · Pizza"])
        // The collapsed row's ring is as of its last payment.
        #expect(drawn.first?.ringFraction == 0.8)
        #expect(drawn.first?.messageIDs.count == 3)
        #expect(drawn.first?.serverID == MessageID(value: 3))
    }

    @Test("66: payments for different requests don't collapse")
    func differentRequestsStayApart() {
        let other = PaymentRequestID(data: Data([2]))
        let drawn = rows(
            [payment(1, by: jordan), payment(2, by: sam, for: other)],
            viewer: alex,
            requests: [tahoeCabin, request(other, title: "Gas", shares: [creatorShare(40), paid(sam, 40, minutes: 2)])]
        )
        #expect(drawn.map(line) == ["Jordan paid you $40 · Tahoe cabin", "Sam paid you $40 · Gas"])
    }

    @Test("66: the creator's collapsed row names them as the payee")
    func collapsedForCreator() {
        let drawn = rows(
            [payment(1, by: jordan), payment(2, by: sam)],
            viewer: alex,
            requests: [request(shares: [creatorShare(40), paid(jordan, 40, minutes: 1), paid(sam, 40, minutes: 2)])]
        )
        #expect(drawn.map(line) == ["2 people paid you $80 · Tahoe cabin"])
    }

    @Test("67: a date header between two payments keeps them apart")
    func midnightSplitsARun() {
        let midnight = Calendar.current.startOfDay(for: noon.addingTimeInterval(24 * 3600))
        let before = (midnight.timeIntervalSince(noon) - 60) / 60
        let after = (midnight.timeIntervalSince(noon) + 60) / 60
        let drawn = items(
            [payment(1, by: jordan, minutes: before), payment(2, by: sam, minutes: after)],
            viewer: alex,
            requests: [request(shares: [creatorShare(40), paid(jordan, 40, minutes: before), paid(sam, 40, minutes: after)])]
        )
        let kinds: [String] = drawn.map {
            switch $0 {
            case .dateSeparator: "date"
            case .requestEvent:  "row"
            case .message, .unreadDivider, .typingIndicator, .encryptionMarker, .systemMessage, .inviteCard: "other"
            }
        }
        #expect(kinds == ["date", "row", "date", "row"])
    }

    @Test("68: the viewer in a run of seven")
    func viewerInARun() {
        let others = (0..<6).map { _ in UserID() }
        let payers = Array(others.prefix(3)) + [sam] + Array(others.suffix(3))
        let shares = [creatorShare()] + payers.enumerated().map { paid($1, minutes: Double($0 + 1)) }
        let messages = payers.enumerated().map { payment(UInt64($0 + 1), by: $1, 10) }
        let drawn = rows(messages, viewer: sam, requests: [request(title: "Pizza", shares: shares)])
        #expect(drawn.map(line) == ["You and 6 others paid $70 · Pizza"])
    }

    @Test("68: the viewer and one other")
    func viewerAndOneOther() {
        let drawn = rows(
            [payment(1, by: jordan), payment(2, by: sam)],
            viewer: sam,
            requests: [request(shares: [creatorShare(40), paid(jordan, 40, minutes: 1), paid(sam, 40, minutes: 2)])]
        )
        #expect(drawn.map(line) == ["You and 1 other paid $80 · Tahoe cabin"])
        // "You" is regular weight on a collapsed row.
        #expect(drawn.flatMap(emphasized).isEmpty)
    }

    @Test("73: a request that isn't stored draws no title or ring and doesn't tap through")
    func missingRequest() throws {
        let row = try #require(rows([payment(1, by: jordan)], viewer: sam).first)
        #expect(line(row) == "Jordan paid Alex $40")
        #expect(row.title == nil)
        #expect(row.ringFraction == nil)
        #expect(row.requestID == nil)
    }

    @Test("A share payment heads the unread divider only for the member it paid")
    func unreadDivider() {
        let messages = [text(1, from: alex), payment(2, by: jordan), text(3, from: alex)]
        func drawn(for viewer: UserID) -> [String] {
            ChatItem.from(
                messages, selfUserID: viewer, nameOf: { names[$0] },
                requests: [tahoe: tahoeCabin],
                unreadBoundary: .at(readThrough: MessageID(value: 1), count: 1)
            ).compactMap {
                switch $0 {
                case .unreadDivider: "divider"
                case .requestEvent:  "row"
                case .message:       "message"
                case .dateSeparator, .typingIndicator, .encryptionMarker, .systemMessage, .inviteCard: nil
                }
            }
        }
        // Sam's divider sits under the payment row, above the text that follows it.
        #expect(drawn(for: sam) == ["message", "row", "divider", "message"])
        // Jordan paid Alex, so for Alex the payment is the first unread row.
        #expect(drawn(for: jordan).firstIndex(of: "divider") == 2)
    }
}

// MARK: - Fit -

@Suite("Share payment row fit (spec cases 69-70)")
struct RequestEventFitTests {

    /// One unit per character, plus a ring the width of two.
    private func width(_ event: ChatRequestEvent) -> ([ChatRequestEvent.Span], String?) -> Double {
        { caption, title in
            var count = caption.map(\.text.count).reduce(0, +)
            if let amount = event.amount { count += 1 + amount.count }
            if let title { count += event.titleSeparator.count + title.count + 2 }
            return Double(count)
        }
    }

    private func event(payer: String, creator: String, title: String?) -> ChatRequestEvent {
        ChatRequestEvent(
            id: "row", kind: .sharePayment,
            caption: [.name(payer), .init(" paid "), .name(creator)],
            amount: "$40", title: title, ringFraction: title == nil ? nil : 0.5
        )
    }

    @Test("A row that fits is left whole")
    func fits() {
        let row = event(payer: "Jordan", creator: "Alex", title: "Tahoe cabin")
        let fit = row.fit(maxWidth: 100, width: width(row))
        #expect(fit.caption == row.caption)
        #expect(fit.title == "Tahoe cabin")
        #expect(!fit.wraps)
    }

    @Test("69: a long title shortens with an ellipsis and stays on one line")
    func shortensTitle() {
        let row = event(payer: "Jordan", creator: "Alex", title: "Tahoe cabin weekend with everyone")
        // Caption 16 + amount 4 + separator 3 + ring 2 leaves 15 for the title.
        let fit = row.fit(maxWidth: 40, width: width(row))
        #expect(!fit.wraps)
        #expect(fit.caption == row.caption)
        #expect(fit.title == "Tahoe cabin we…")
    }

    @Test("69: the title never shortens under eight characters")
    func titleFloor() throws {
        let row = event(payer: "Maximiliana", creator: "Bartholomew", title: "Tahoe cabin weekend")
        // Title at its floor (8) costs 13 with separator and ring; amount 4; " paid " 6. 37 leaves
        // 14 for two names, which fit only once both are cut.
        let fit = row.fit(maxWidth: 37, width: width(row))
        #expect(!fit.wraps)
        #expect(fit.title == "Tahoe c…")
        let cut = fit.caption.filter(\.isName).map(\.text)
        #expect(cut.allSatisfy { $0.count >= ChatRequestEvent.shortestName && $0.hasSuffix("…") })
        #expect(cut.map(\.count).reduce(0, +) == 14)
    }

    @Test("70: what still doesn't fit wraps the title and ring to a second line")
    func wraps() {
        let row = event(payer: "Maximiliana", creator: "Bartholomew", title: "Tahoe cabin weekend")
        // Both names at their floor (6 + 6) still leave the line at 35.
        let fit = row.fit(maxWidth: 30, width: width(row))
        #expect(fit.wraps)
        // The whole title moves down; the second line truncates it at its own end.
        #expect(fit.title == "Tahoe cabin weekend")
        // The first line holds caption and amount alone, so the names get back what fits in 30.
        let first = fit.caption.map(\.text).joined()
        #expect(first.count + 4 <= 30)
        #expect(fit.caption.filter(\.isName).map(\.text.count).reduce(0, +) == 20)
    }

    @Test("A row with no title only shortens names")
    func noTitle() {
        let row = event(payer: "Maximiliana", creator: "Bartholomew", title: nil)
        let fit = row.fit(maxWidth: 24, width: width(row))
        #expect(!fit.wraps)
        #expect(fit.title == nil)
    }
}

// MARK: - Marked paid and closed -

@Suite("Marked-paid and closed rows (spec cases 75-82)")
struct MarkedPaidAndClosedRowTests {

    @Test("75: the marked-paid row reads per viewer, at the share's paid_at", arguments: [
        (alex, "You marked Sam as paid · Tahoe cabin", ["Sam"]),
        (sam, "Alex marked you as paid · Tahoe cabin", ["Alex"]),
        (jordan, "Alex marked Sam as paid · Tahoe cabin", ["Alex", "Sam"]),
    ])
    func markedCopy(viewer: UserID, expected: String, semibold: [String]) {
        let stored = request(shares: [creatorShare(40), marked(sam, 40, minutes: 2), owed(jordan, 40)])
        let drawn = items([text(1, from: alex), text(3, from: jordan)], viewer: viewer, requests: [stored])
        let index = drawn.firstIndex { if case .requestEvent = $0 { true } else { false } }
        guard let index, case .requestEvent(let row) = drawn[index] else {
            Issue.record("no marked-paid row")
            return
        }
        #expect(line(row) == expected)
        #expect(emphasized(row) == semibold)
        #expect(row.kind == .markedPaid)
        #expect(row.amount == nil)
        #expect(row.serverID == nil)
        // Between the message before its time and the one after.
        #expect(drawn[index - 1].messageID == text(1, from: alex).stableID)
        #expect(drawn[index + 1].messageID == text(3, from: jordan).stableID)
    }

    @Test("76: the marked-paid row's ring counts the mark; the payment row before it doesn't")
    func ringAcrossPaymentAndMark() {
        let b = UserID(), c = UserID(), d = UserID()
        let four = request(shares: [creatorShare(), paid(b, minutes: 1), marked(c, minutes: 2), owed(d)])
        let drawn = rows([payment(1, by: b, 10), text(3, from: sam)], viewer: sam, requests: [four], extraNames: [c: "Cam"])
        #expect(drawn.map(\.kind) == [.sharePayment, .markedPaid])
        #expect(drawn.map(\.ringFraction) == [0.5, 0.75])
        #expect(drawn.last?.amount == nil)
    }

    @Test("77: a payment that replaces the mark leaves only the payment row")
    func paymentReplacesMark() {
        let stored = request(shares: [creatorShare(40), paid(sam, 40, minutes: 2), owed(jordan, 40)])
        let drawn = rows([text(1, from: alex), payment(2, by: sam)], viewer: jordan, requests: [stored])
        #expect(drawn.map(line) == ["Sam paid Alex $40 · Tahoe cabin"])
    }

    @Test("78: the closed row reads per viewer, at closed_at, with no ring", arguments: [
        (alex, "You closed Tahoe cabin"),
        (sam, "Alex closed Tahoe cabin"),
    ])
    func closedCopy(viewer: UserID, expected: String) throws {
        let stored = request(shares: [creatorShare(40), owed(sam, 40)], status: .closed, closedAt: noon.addingTimeInterval(120))
        let row = try #require(rows([text(1, from: alex)], viewer: viewer, requests: [stored]).first)
        #expect(line(row) == expected)
        #expect(row.kind == .closed)
        #expect(row.ringFraction == nil)
        #expect(row.requestID == tahoe.data)
    }

    @Test("79: a completed or expired request draws no closed row", arguments: [GroupPaymentRequest.Status.completed, .expired])
    func noRowForOtherEndings(status: GroupPaymentRequest.Status) {
        let stored = request(shares: [creatorShare(40), owed(sam, 40)], status: status, closedAt: noon.addingTimeInterval(120))
        #expect(rows([text(1, from: alex)], viewer: sam, requests: [stored]).isEmpty)
    }

    @Test("80: marks in a row collapse")
    func marksCollapse() {
        let b = UserID(), c = UserID()
        let stored = request(shares: [creatorShare(), marked(b, minutes: 2), marked(c, minutes: 3), marked(jordan, minutes: 4), owed(sam)])
        #expect(rows([text(1, from: alex)], viewer: sam, requests: [stored]).map(line) == ["Alex marked 3 people as paid · Tahoe cabin"])
        #expect(rows([text(1, from: alex)], viewer: jordan, requests: [stored]).map(line) == ["Alex marked you and 2 others as paid · Tahoe cabin"])
        #expect(rows([text(1, from: alex)], viewer: alex, requests: [stored]).map(line) == ["You marked 3 people as paid · Tahoe cabin"])
    }

    @Test("80: a mark and a close for one request stay two rows")
    func markThenClose() {
        let stored = request(shares: [creatorShare(40), marked(sam, 40, minutes: 2)], status: .closed, closedAt: noon.addingTimeInterval(180))
        #expect(rows([text(1, from: alex)], viewer: jordan, requests: [stored]).map(\.kind) == [.markedPaid, .closed])
    }

    @Test("81: a stored row is no message: it carries nothing the read pointer or a jump can land on")
    func storedRowIsNotAMessage() throws {
        let stored = request(shares: [creatorShare(40), marked(sam, 40, minutes: 2)])
        let row = try #require(rows([text(1, from: alex)], viewer: jordan, requests: [stored]).first)
        #expect(row.serverID == nil)
        #expect(row.messageIDs.isEmpty)
        #expect(ChatItem.requestEvent(row).messageID == nil)
    }

    @Test("82: a mark older than the oldest loaded message draws no row until paging reaches it")
    func olderThanTheWindow() {
        let stored = request(shares: [creatorShare(40), marked(sam, 40, minutes: 2)])
        #expect(rows([text(5, from: alex), text(6, from: jordan)], viewer: jordan, requests: [stored]).isEmpty)
        #expect(rows([text(1, from: alex), text(5, from: alex), text(6, from: jordan)], viewer: jordan, requests: [stored]).count == 1)
    }

    @Test("A stored row on a later day gets its own date header")
    func storedRowDateHeader() {
        let stored = request(shares: [creatorShare(40), marked(sam, 40, minutes: 26 * 60)])
        let drawn = items([text(1, from: alex)], viewer: jordan, requests: [stored])
        guard drawn.count == 4, case .dateSeparator = drawn[2], case .requestEvent = drawn[3] else {
            Issue.record("expected date, message, date, row; got \(drawn.count) items")
            return
        }
    }
}

// MARK: - Preview, unread and persistence -

@MainActor
@Suite("Share payment preview, unread and persistence (spec cases 71, 72, 74, 81)")
struct SharePaymentListTests {

    private func makeController(viewer: UserID, database: Database) -> ConversationController {
        let mock = MockConversations()
        return ConversationController(
            fetching: mock, membership: mock, viewerSettings: mock, messaging: mock, streaming: mock,
            contactNaming: MockDMContactNaming(),
            database: database,
            owner: .generate()!, selfUserID: viewer
        )
    }

    /// A group whose latest message is Jordan's share payment (id 3, stamp 3), over Alex's text
    /// (id 2, stamp 2), with the viewer's READ watermark at `read`.
    private func group(viewer: UserID, read: UInt64, latest: ConversationMessage? = nil) -> Conversation {
        Conversation(
            id: chat,
            members: [alex, jordan, sam].map {
                ConversationMember(userID: $0, displayName: names[$0]!, readPointer: $0 == viewer ? MessageID(value: read) : nil)
            },
            lastMessage: latest ?? payment(3, by: jordan),
            lastActivity: noon,
            type: .group
        )
    }

    private func preview(_ controller: ConversationController, _ conversation: Conversation, title: String? = "Tahoe cabin") -> String? {
        controller.lastMessagePreview(for: conversation, requestTitle: { _ in title }) { _ in nil }
    }

    @Test("71, 72: the preview reads per viewer, with 'for' in place of the dot", arguments: [
        (alex, "Jordan paid you $40 for Tahoe cabin"),
        (sam, "Jordan paid Alex $40 for Tahoe cabin"),
        (jordan, "You paid $40 for Tahoe cabin"),
    ])
    func previewPerViewer(viewer: UserID, expected: String) throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let controller = makeController(viewer: viewer, database: database)
        #expect(preview(controller, group(viewer: viewer, read: 2)) == expected)
    }

    @Test("The preview drops 'for <title>' when the title can't be read")
    func previewWithoutTitle() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let controller = makeController(viewer: sam, database: database)
        #expect(preview(controller, group(viewer: sam, read: 2), title: nil) == "Jordan paid Alex $40")
    }

    @Test("71: the creator's chat is unread, and counts the payment")
    func unreadForCreator() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let controller = makeController(viewer: alex, database: database)
        let conversation = group(viewer: alex, read: 2)
        try database.upsertConversation(conversation)
        try database.upsertConversationMessages([text(2, from: alex), payment(3, by: jordan)], conversationID: chat)
        #expect(controller.hasUnreadMessages(conversation))
        #expect(controller.unreadCount(for: conversation) == 1)
    }

    @Test("72: another member's chat stays read when the payment is all that's new")
    func readForOtherMember() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let controller = makeController(viewer: sam, database: database)
        let conversation = group(viewer: sam, read: 2)
        try database.upsertConversation(conversation)
        try database.upsertConversationMessages([text(2, from: alex), payment(3, by: jordan)], conversationID: chat)
        #expect(!controller.hasUnreadMessages(conversation))
        #expect(controller.unreadCount(for: conversation) == 0)
    }

    @Test("72: another member's count leaves out a payment that sits among unread messages")
    func countSkipsPaymentForOtherMember() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let controller = makeController(viewer: sam, database: database)
        // Read through 1; then Alex's text (2), Jordan's payment (3), Alex's text (4), and the
        // payment again as the latest (5).
        let conversation = group(viewer: sam, read: 1, latest: payment(5, by: jordan))
        try database.upsertConversation(conversation)
        try database.upsertConversationMessages(
            [text(1, from: alex), text(2, from: alex), payment(3, by: jordan), text(4, from: alex), payment(5, by: jordan)],
            conversationID: chat
        )
        #expect(controller.hasUnreadMessages(conversation))
        // Stamps 2...4 are three messages; one is a payment to Alex.
        #expect(controller.unreadCount(for: conversation) == 2)
        #expect(preview(controller, conversation) == "Jordan paid Alex $40 for Tahoe cabin")
    }

    @Test("74: a stored share payment reads back with its request id")
    func persistsRequestID() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        try database.upsertConversation(group(viewer: sam, read: 0))
        try database.upsertConversationMessages([payment(3, by: jordan), text(4, from: alex)], conversationID: chat)
        let stored = try database.messages(conversationID: chat, from: 0)
        let reloaded = try #require(stored.first { $0.id.value == 3 })
        #expect(reloaded.paymentRequestID == tahoe)
        #expect(reloaded.isSharePayment)
        #expect(stored.first { $0.id.value == 4 }?.paymentRequestID == nil)
        // And it still draws as a share payment row.
        #expect(rows(stored, viewer: sam).first?.kind == .sharePayment)
    }
}
