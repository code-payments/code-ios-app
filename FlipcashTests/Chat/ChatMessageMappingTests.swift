//
//  ChatMessageMappingTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashCore
import FlipcashUI
@testable import Flipcash

@MainActor
@Suite("ChatItem mapping from conversation")
struct ChatMessageMappingTests {

    private let me = UUID()
    private let them = UUID()
    /// 9am local, so every offset the suite adds stays on one day whatever timezone the test runs
    /// in — a change of day is its own reason to break a run, and only one case here means to.
    private let base = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_000_000))
        .addingTimeInterval(9 * 60 * 60)

    private func text(_ id: UInt64, _ sender: UUID, _ body: String, after offset: TimeInterval) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id),
            senderID: sender,
            content: .text(body),
            date: base.addingTimeInterval(offset),
            unreadSeq: id
        )
    }

    private func reply(_ id: UInt64, _ sender: UUID, _ body: String, to repliedTo: UInt64, after offset: TimeInterval) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id),
            senderID: sender,
            content: .text(body),
            date: base.addingTimeInterval(offset),
            unreadSeq: id,
            repliedTo: MessageID(value: repliedTo)
        )
    }

    /// The message rows, dropping the interleaved date separators.
    private func messageRows(_ items: [ChatItem]) -> [ChatMessage] {
        items.compactMap { if case .message(let message) = $0 { message } else { nil } }
    }

    private func separatorCount(_ items: [ChatItem]) -> Int {
        items.filter { if case .dateSeparator = $0 { true } else { false } }.count
    }

    private func receiptText(_ items: [ChatItem]) -> String? {
        items.compactMap { if case .message(let message) = $0 { message.receipt?.displayText } else { nil } }.last
    }

    private func sending(_ clientID: UUID, _ body: String, after offset: TimeInterval) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: .max), senderID: me, content: .text(body),
            date: base.addingTimeInterval(offset), unreadSeq: 0,
            status: .sending, clientMessageID: clientID
        )
    }

    private func failedFlags(_ items: [ChatItem]) -> [Bool] {
        messageRows(items).map(\.isFailed)
    }

    private func deleted(_ id: UInt64, _ sender: UUID, deletedBy: UUID? = nil, after offset: TimeInterval) -> ConversationMessage {
        ConversationMessage(id: MessageID(value: id), senderID: sender, content: .deleted(.init(deletedBy: deletedBy ?? sender, deletedAt: base.addingTimeInterval(offset))), date: base.addingTimeInterval(offset), unreadSeq: id, eventSequence: id)
    }

    /// A message that arrived encrypted: decrypted to `body`, failed for `failure`, or still
    /// waiting on the peer's key when both are nil.
    private func encrypted(
        _ id: UInt64,
        _ sender: UUID,
        _ body: String? = nil,
        failure: ConversationMessage.DecryptFailure? = nil,
        after offset: TimeInterval = 0
    ) -> ConversationMessage {
        let sealed = ConversationMessage.Sealed(scheme: 1, nonce: Data([1]), ciphertext: Data([2]))
        return ConversationMessage(
            id: MessageID(value: id),
            senderID: sender,
            content: body.map { .text($0) } ?? .encrypted(scheme: sealed.scheme, nonce: sealed.nonce, ciphertext: sealed.ciphertext),
            date: base.addingTimeInterval(offset),
            unreadSeq: id,
            sealed: sealed,
            decryptFailure: failure
        )
    }

    private func markerIndex(_ items: [ChatItem]) -> Int? {
        items.firstIndex { if case .encryptionMarker = $0 { true } else { false } }
    }

    private func index(of body: String, in items: [ChatItem]) -> Int? {
        items.firstIndex { if case .message(let message) = $0 { message.content == .text(body) } else { false } }
    }

    @Test("a message that failed to decrypt draws as unavailable, with the hint its cause calls for")
    func decryptFailureHints() {
        func hint(_ sender: UUID, _ failure: ConversationMessage.DecryptFailure) -> [ChatMessage.Content] {
            messageRows(ChatItem.from([encrypted(1, sender, failure: failure)], selfUserID: me, counterpartName: "Ada Lovelace"))
                .map(\.content)
        }
        #expect(hint(them, .unsupported) == [.unavailable(.updateApp)])
        #expect(hint(me, .unsupported) == [.unavailable(.updateApp)])
        #expect(hint(them, .authentication) == [.unavailable(.askToResend(firstName: "Ada"))])
        #expect(hint(me, .authentication) == [.unavailable(.resend)])
    }

    @Test("a message waiting on the peer's key is left out, not drawn as unavailable")
    func awaitingDecryptionIsHidden() {
        let items = ChatItem.from([text(1, them, "hi", after: 0), encrypted(2, them, after: 30)], selfUserID: me)
        #expect(messageRows(items).map(\.content) == [.text("hi")])
        #expect(markerIndex(items) == nil)
    }

    @Test("the marker sits above the first encrypted message, below the plaintext before it")
    func markerWhereCiphertextStarts() throws {
        let items = ChatItem.from(
            [text(1, them, "old", after: 0), encrypted(2, them, "new", after: 30), encrypted(3, me, "newer", after: 60)],
            selfUserID: me,
            headsHistory: false
        )
        let marker = try #require(markerIndex(items))
        let old = try #require(index(of: "old", in: items))
        let new = try #require(index(of: "new", in: items))
        #expect(old < marker && marker < new)
        #expect(items.filter { if case .encryptionMarker = $0 { true } else { false } }.count == 1)
        // The marker breaks the run: the first encrypted message doesn't group onto the plaintext above.
        #expect(messageRows(items).first { $0.content == .text("new") }?.isContinuationFromPrevious == false)
    }

    @Test("an all-encrypted transcript gets the marker at its head only once the head is loaded")
    func markerAtHeadOfHistory() {
        let messages = [encrypted(1, them, "a", after: 0), encrypted(2, me, "b", after: 30)]
        let whole = ChatItem.from(messages, selfUserID: me, headsHistory: true)
        #expect(markerIndex(whole) == 0)
        #expect(markerIndex(ChatItem.from(messages, selfUserID: me, headsHistory: false)) == nil)
    }

    @Test("a plaintext transcript has no marker, whatever the chat's flag says")
    func noMarkerWithoutCiphertext() {
        #expect(markerIndex(ChatItem.from([text(1, them, "hi", after: 0)], selfUserID: me)) == nil)
    }

    @Test("a deleted tombstone is dropped: no stray separator, no grouping to an invisible row, receipt intact")
    func deletedTombstoneIsDroppedCleanly() {
        // A tombstone opens the transcript, then a real same-sender message shortly after.
        let items = ChatItem.from([deleted(1, them, after: 0), text(2, them, "hi", after: 30)], selfUserID: me)
        let rows = messageRows(items)
        #expect(rows.count == 1)                     // tombstone not rendered
        #expect(rows[0].content == .text("hi"))
        #expect(!rows[0].isContinuationFromPrevious) // not grouped to the invisible tombstone
        #expect(separatorCount(items) == 1)          // one separator for the real message, no orphan

        // A tombstone as the newest self message must not steal the "Delivered" receipt from the last visible one.
        let withReceipt = ChatItem.from([text(1, me, "hello", after: 0), deleted(2, me, after: 60)], selfUserID: me)
        #expect(receiptText(withReceipt) == "Delivered")
    }

    @Test("Same-sender run within the gap groups; a sender change breaks it; gaps add separators")
    func grouping() {
        let messages = [
            text(1, me, "a", after: 0),
            text(2, me, "b", after: 60),               // +1m, same sender → grouped with #1
            text(3, them, "c", after: 120),            // other sender → breaks the run
            text(4, me, "d", after: 120 + 4 * 60 * 60) // me again, but a gap from #3 → standalone
        ]

        let items = ChatItem.from(messages, selfUserID: me)
        let rows = messageRows(items)

        #expect(rows.map(\.sender) == [.me, .me, .other, .me])
        #expect(rows[0].content == .text("a"))
        #expect(rows[0].isContinuedByNext)           // #1 → #2 same-sender run
        #expect(rows[1].isContinuationFromPrevious)
        #expect(!rows[1].isContinuedByNext)          // #2 → #3 sender change
        #expect(!rows[2].isContinuationFromPrevious)
        #expect(!rows[2].isContinuedByNext)
        #expect(!rows[3].isContinuationFromPrevious) // gap from #3
        // One separator opens the transcript; another breaks the four-hour gap before #4.
        #expect(separatorCount(items) == 2)
    }

    @Test("A pause of minutes keeps a same-sender run together; a pause past the gap breaks it")
    func gapBreaksRun() {
        // Anchored to a local morning so neither pause can reach midnight and break the run for the
        // other reason, whatever timezone the test runs in.
        func pair(_ pause: TimeInterval) -> [ChatMessage] {
            let start = base
            let rows = [
                ConversationMessage(id: MessageID(value: 1), senderID: me, content: .text("a"), date: start, unreadSeq: 1),
                ConversationMessage(id: MessageID(value: 2), senderID: me, content: .text("b"), date: start.addingTimeInterval(pause), unreadSeq: 2),
            ]
            return messageRows(ChatItem.from(rows, selfUserID: me))
        }

        // The window is Android's, so a lull long enough to leave the app and come back is still
        // one exchange rather than a column of separated single bubbles.
        let grouped = pair(40 * 60)
        #expect(grouped[0].isContinuedByNext)
        #expect(grouped[1].isContinuationFromPrevious)

        let broken = pair(4 * 60 * 60)
        #expect(!broken[0].isContinuedByNext)
        #expect(!broken[1].isContinuationFromPrevious)
    }

    @Test("A run does not carry across a change of day, however short the pause")
    func dayChangeBreaksRun() {
        // Straddling local midnight, so the two rows are minutes apart but on different dates.
        let midnight = Calendar.current.startOfDay(for: base.addingTimeInterval(24 * 60 * 60))
        let before = ConversationMessage(
            id: MessageID(value: 1), senderID: me, content: .text("a"),
            date: midnight.addingTimeInterval(-60), unreadSeq: 1
        )
        let after = ConversationMessage(
            id: MessageID(value: 2), senderID: me, content: .text("b"),
            date: midnight.addingTimeInterval(60), unreadSeq: 2
        )

        let items = ChatItem.from([before, after], selfUserID: me)
        let rows = messageRows(items)

        #expect(!rows[0].isContinuedByNext)
        #expect(!rows[1].isContinuationFromPrevious)
        #expect(separatorCount(items) == 2) // one opening the transcript, one heading the new day
    }

    @Test("Cash messages map to formatted cash content with a currency flag")
    func cash() {
        let fiat = ExchangedFiat(
            nativeAmount: FiatAmount(value: 5, currency: .usd),
            rate: Rate(fx: 1, currency: .usd)
        )
        let messages = [
            ConversationMessage(id: MessageID(value: 1), senderID: them, content: .cash(fiat), date: base, unreadSeq: 1),
        ]

        let rows = messageRows(ChatItem.from(messages, selfUserID: me))

        #expect(rows.count == 1)
        #expect(rows[0].sender == .other) // sent by `them`, not me → received
        guard case .cash(let cash) = rows[0].content else {
            Issue.record("expected cash content, got \(rows[0].content)")
            return
        }
        #expect(cash.token == "Cash")
        #expect(cash.amount == fiat.nativeAmount.formatted())
        #expect(cash.flagImageName != nil) // currency flag derived from the currency
        #expect(!cash.isTip) // no cash action → plain send
        #expect(ChatCashContent.caption(isFromSelf: false, isTip: cash.isTip) == "You received")
    }

    @Test("Photo messages map to media content, a redacted one staying a photo", arguments: [false, true])
    func media(redacted: Bool) {
        let attachment = MediaAttachment(blobID: BlobID(data: Data([9, 8, 7])), width: 300, height: 400, blurhash: "LEHV6nWB2yk8")
        let messages = [
            ConversationMessage(
                id: MessageID(value: 1),
                senderID: them,
                content: .media([attachment], caption: "hi"),
                date: base,
                unreadSeq: 1,
                redacted: redacted
            ),
        ]

        let rows = messageRows(ChatItem.from(messages, selfUserID: me))

        #expect(rows.map(\.content) == [.media(ChatMediaContent(
            blobID: attachment.blobID,
            width: 300,
            height: 400,
            blurhash: "LEHV6nWB2yk8",
            caption: "hi",
            isRedacted: redacted
        ))])
    }

    @Test("Tipped cash messages carry the tip flag and caption")
    func tippedCash() {
        let fiat = ExchangedFiat(
            nativeAmount: FiatAmount(value: 5, currency: .usd),
            rate: Rate(fx: 1, currency: .usd)
        )
        let messages = [
            ConversationMessage(id: MessageID(value: 1), senderID: them, content: .cash(fiat), cashAction: .tipped, date: base, unreadSeq: 1),
        ]

        let rows = messageRows(ChatItem.from(messages, selfUserID: me))

        guard case .cash(let cash) = rows.first?.content else {
            Issue.record("expected cash content")
            return
        }
        #expect(cash.isTip)
        #expect(ChatCashContent.caption(isFromSelf: false, isTip: cash.isTip) == "You received a tip")
    }

    @Test("The latest sent message reads Delivered until the read pointer reaches it")
    func receiptDelivered() {
        let items = ChatItem.from(
            [text(1, me, "hi", after: 0)],
            selfUserID: me,
            counterpartRead: (pointer: MessageID(value: 0), date: nil)
        )
        #expect(receiptText(items) == "Delivered")
    }

    @Test("A read pointer without a timestamp reads Read")
    func receiptReadWithoutDate() {
        let items = ChatItem.from(
            [text(1, me, "hi", after: 0)],
            selfUserID: me,
            counterpartRead: (pointer: MessageID(value: 1), date: nil)
        )
        #expect(receiptText(items) == "Read")
    }

    @Test("Read stays on the last read message while a newer one shows Delivered")
    func readAndDeliveredSplit() {
        let items = ChatItem.from(
            [text(1, me, "a", after: 0), text(2, me, "b", after: 60), text(3, me, "c", after: 120)],
            selfUserID: me,
            counterpartRead: (pointer: MessageID(value: 2), date: nil)
        )
        #expect(messageRows(items).map { $0.receipt?.status } == [nil, "Read", "Delivered"])
    }

    @Test("When the newest message is read, it carries the only line")
    func readReachesNewest() {
        let items = ChatItem.from(
            [text(1, me, "a", after: 0), text(2, me, "b", after: 60)],
            selfUserID: me,
            counterpartRead: (pointer: MessageID(value: 2), date: nil)
        )
        #expect(messageRows(items).map { $0.receipt?.status } == [nil, "Read"])
    }

    @Test("Read skips the counterpart's own messages to land on the last read self message")
    func readSkipsCounterpart() {
        let items = ChatItem.from(
            [text(1, me, "a", after: 0), text(2, them, "b", after: 60), text(3, me, "c", after: 120)],
            selfUserID: me,
            counterpartRead: (pointer: MessageID(value: 2), date: nil)
        )
        #expect(messageRows(items).map { $0.receipt?.status } == ["Read", nil, "Delivered"])
    }

    @Test("A receipt between two of my bubbles keeps them apart; once it moves on they join")
    func receiptBreaksBubbleRun() {
        let messages = [text(1, me, "a", after: 0), text(2, me, "b", after: 60)]
        let settling = messageRows(ChatItem.from(messages, selfUserID: me, suppressReceiptFor: "2"))
        #expect(settling.map { $0.receipt?.status } == ["Delivered", nil])
        #expect(!settling[0].joinsBubbleBelow)
        #expect(!settling[1].joinsBubbleAbove)

        let handedOff = messageRows(ChatItem.from(messages, selfUserID: me))
        #expect(handedOff.map { $0.receipt?.status } == [nil, "Delivered"])
        #expect(handedOff[0].joinsBubbleBelow)
        #expect(handedOff[1].joinsBubbleAbove)
    }

    @Test("A Read line left above a Delivered one keeps the run broken there")
    func readLineBreaksBubbleRun() {
        let rows = messageRows(ChatItem.from(
            [text(1, me, "a", after: 0), text(2, me, "b", after: 60)],
            selfUserID: me,
            counterpartRead: (pointer: MessageID(value: 1), date: nil)
        ))
        #expect(rows.map { $0.receipt?.status } == ["Read", "Delivered"])
        #expect(!rows[0].joinsBubbleBelow)
    }

    @Test("A settling send keeps the Read line where it is and shows no Delivered yet")
    func settlingSendKeepsRead() {
        let items = ChatItem.from(
            [text(1, me, "a", after: 0), text(2, me, "b", after: 60)],
            selfUserID: me,
            counterpartRead: (pointer: MessageID(value: 1), date: nil),
            suppressReceiptFor: "2"
        )
        #expect(messageRows(items).map { $0.receipt?.status } == ["Read", nil])
    }

    @Test("Appending one sent message is a single clean insert — the receipt rides on the message")
    func appendingOneMessageIsACleanInsert() {
        // Two of my messages, then I append a third (same sender, within the grouping gap).
        let before = ChatItem.from([text(1, me, "a", after: 0), text(2, me, "b", after: 60)], selfUserID: me)
        let after = ChatItem.from([text(1, me, "a", after: 0), text(2, me, "b", after: 60), text(3, me, "c", after: 120)], selfUserID: me)

        let beforeByID = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0) })
        let afterByID = Dictionary(uniqueKeysWithValues: after.map { ($0.id, $0) })
        let beforeIDs = Set(beforeByID.keys)
        let afterIDs = Set(afterByID.keys)

        let inserted = afterIDs.subtracting(beforeIDs)
        let deleted = beforeIDs.subtracting(afterIDs)
        let reconfigured = beforeIDs.intersection(afterIDs).filter { beforeByID[$0] != afterByID[$0] }
        func receipt(_ id: String) -> String? {
            if case .message(let m) = afterByID[id] { m.receipt?.displayText } else { nil }
        }

        // The delivery line rides on the message, so there is no separate receipt row to insert or
        // delete — appending is purely the new bubble. ChatLayout receives one clean insert.
        #expect(inserted == ["3"])
        #expect(deleted.isEmpty)
        // The previous bubble reconfigures in place — it both loses the receipt and flips its grouping
        // flag — via reconfigureItems, which does not animate as an insert/delete.
        #expect(reconfigured == ["2"])
        // Concretely: the receipt moved from the old latest bubble onto the new one.
        #expect(receipt("3") == "Delivered")
        #expect(receipt("2") == nil)
    }

    @Test("A read from days ago renders the relative day, not a bare time")
    func receiptUsesRelativeDay() {
        // Guards the hookup: with the old `formattedTime()` this read as "Read 3:42 PM".
        let calendar = Calendar.current
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: noon)!
        let weekday = calendar.weekdaySymbols[calendar.component(.weekday, from: threeDaysAgo) - 1]

        let items = ChatItem.from(
            [text(1, me, "hi", after: 0)],
            selfUserID: me,
            counterpartRead: (pointer: MessageID(value: 1), date: threeDaysAgo)
        )
        #expect(receiptText(items) == "Read \(weekday)")
    }

    @Test("A sending row shows no status line and keeps the prior delivered receipt")
    func sendingMapsToState() {
        let clientID = UUID()
        let items = ChatItem.from(
            [text(1, me, "a", after: 0), sending(clientID, "b", after: 60)],
            selfUserID: me,
            counterpartRead: (pointer: MessageID(value: 0), date: nil)
        )
        #expect(failedFlags(items) == [false, false])
        // "b" (sending) shows nothing; the prior delivered "a" keeps its "Delivered" line.
        let rows = messageRows(items)
        #expect(rows.first?.receipt?.displayText == "Delivered")
        #expect(rows.last?.id == clientID.uuidString)
        #expect(rows.last?.receipt == nil)
    }

    @Test("A failed row shows its own line without stripping the prior delivered receipt")
    func failedMapsToState() {
        let clientID = UUID()
        var msg = sending(clientID, "b", after: 60)
        msg.status = .failed
        let items = ChatItem.from(
            [text(1, me, "a", after: 0), msg],
            selfUserID: me,
            counterpartRead: (pointer: MessageID(value: 0), date: nil)
        )
        #expect(failedFlags(items) == [false, true])
        let rows = messageRows(items)
        #expect(rows.first?.receipt?.displayText == "Delivered")                     // prior delivered receipt preserved
        #expect(rows.last?.receipt?.displayText == "Not Delivered. Tap to retry")    // failed row shows its own line
    }

    @Test("A settling send's Delivered receipt is held back, then shows once the gate clears")
    func suppressedReceiptWhileSettling() {
        let read = (pointer: MessageID(value: 0), date: Date?.none)
        // While the row is still settling (its id is suppressed), no receipt shows.
        let settling = ChatItem.from([text(1, me, "hi", after: 0)], selfUserID: me, counterpartRead: read, suppressReceiptFor: "1")
        #expect(receiptText(settling) == nil)
        // Once the gate clears, "Delivered" appears.
        let settled = ChatItem.from([text(1, me, "hi", after: 0)], selfUserID: me, counterpartRead: read)
        #expect(receiptText(settled) == "Delivered")
    }

    /// A send the server has confirmed, still identified by the client id the settle gate holds.
    private func confirmedSend(_ id: UInt64, _ clientID: UUID, _ body: String, after offset: TimeInterval) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id), senderID: me, content: .text(body),
            date: base.addingTimeInterval(offset), unreadSeq: id,
            status: .sent, clientMessageID: clientID
        )
    }

    @Test("A confirmed send that is still settling leaves the receipt on the previous confirmed row")
    func settlingSendLeavesReceiptOnPreviousRow() {
        let clientID = UUID()
        let items = ChatItem.from(
            [text(1, me, "a", after: 0), text(2, them, "b", after: 30), confirmedSend(3, clientID, "c", after: 60)],
            selfUserID: me,
            counterpartRead: (pointer: MessageID(value: 0), date: nil),
            suppressReceiptFor: clientID.uuidString
        )
        let rows = messageRows(items)
        #expect(rows.map(\.receipt) == [.delivered, nil, nil])
    }

    @Test("Once the settle gate releases, the receipt is on the new row only")
    func releasedSendTakesTheReceipt() {
        let clientID = UUID()
        let items = ChatItem.from(
            [text(1, me, "a", after: 0), text(2, them, "b", after: 30), confirmedSend(3, clientID, "c", after: 60)],
            selfUserID: me,
            counterpartRead: (pointer: MessageID(value: 0), date: nil)
        )
        let rows = messageRows(items)
        #expect(rows.map(\.receipt) == [nil, nil, .delivered])
    }

    @Test("The held line reads as whatever the previous row has earned, Read included")
    func settlingSendKeepsPreviousRead() {
        let clientID = UUID()
        let items = ChatItem.from(
            [text(1, me, "a", after: 0), confirmedSend(2, clientID, "b", after: 60)],
            selfUserID: me,
            counterpartRead: (pointer: MessageID(value: 1), date: nil),
            suppressReceiptFor: clientID.uuidString
        )
        #expect(messageRows(items).map(\.receipt) == [.read(time: nil), nil])
    }

    @Test("A sending row behind a settling hold leaves the previous row's receipt as it was")
    func sendingRowWhileHeldKeepsPreviousReceipt() {
        let clientID = UUID()
        let items = ChatItem.from(
            [text(1, me, "a", after: 0), sending(clientID, "b", after: 60)],
            selfUserID: me,
            counterpartRead: (pointer: MessageID(value: 0), date: nil),
            suppressReceiptFor: clientID.uuidString
        )
        #expect(messageRows(items).map(\.receipt) == [.delivered, nil])
    }

    @Test("A failed row behind a settling hold shows its own line and keeps the previous receipt")
    func failedRowWhileHeldKeepsPreviousReceipt() {
        let clientID = UUID()
        var failed = sending(clientID, "b", after: 60)
        failed.status = .failed
        let items = ChatItem.from(
            [text(1, me, "a", after: 0), failed],
            selfUserID: me,
            counterpartRead: (pointer: MessageID(value: 0), date: nil),
            suppressReceiptFor: clientID.uuidString
        )
        #expect(messageRows(items).map(\.receipt) == [.delivered, .failed("Not Delivered. Tap to retry")])
    }

    @Test("A settling first send shows no receipt anywhere until the gate releases")
    func settlingFirstSendShowsNothing() {
        let clientID = UUID()
        let items = ChatItem.from(
            [text(1, them, "a", after: 0), confirmedSend(2, clientID, "b", after: 60)],
            selfUserID: me,
            counterpartRead: (pointer: MessageID(value: 0), date: nil),
            suppressReceiptFor: clientID.uuidString
        )
        #expect(messageRows(items).map(\.receipt) == [nil, nil])
    }

    @Test("A text message containing a URL carries the trailing link as its preview")
    func textWithURL_hasLinkPreview() {
        let rows = messageRows(ChatItem.from([text(1, me, "check https://apple.com", after: 0)], selfUserID: me))
        #expect(rows.first?.linkPreview?.url?.absoluteString == "https://apple.com")
    }

    @Test("A URL-only message has a link preview")
    func urlOnlyMessage_hasLinkPreview() {
        let rows = messageRows(ChatItem.from([text(1, me, "https://apple.com", after: 0)], selfUserID: me))
        #expect(rows.first?.linkPreview?.url != nil)
    }

    @Test("A plain text message has no link preview")
    func plainText_noLinkPreview() {
        let rows = messageRows(ChatItem.from([text(1, me, "hello there", after: 0)], selfUserID: me))
        #expect(rows.first?.linkPreview == nil)
    }

    @Test("A cash message never carries a link preview")
    func cashMessage_noLinkPreview() {
        let fiat = ExchangedFiat(nativeAmount: FiatAmount(value: 5, currency: .usd), rate: Rate(fx: 1, currency: .usd))
        let rows = messageRows(ChatItem.from(
            [ConversationMessage(id: MessageID(value: 1), senderID: them, content: .cash(fiat), date: base, unreadSeq: 1)],
            selfUserID: me
        ))
        #expect(rows.first?.linkPreview == nil)
    }

    @Test("In placeholder mode my own deletion reads as mine")
    func placeholderNamesTheDeleter() {
        let items = ChatItem.from(
            [deleted(1, me, deletedBy: me, after: 0)],
            selfUserID: me,
            deletedPresentation: .placeholder
        )
        #expect(messageRows(items).first?.content == .deleted("You deleted this message"))
    }

    @Test("In placeholder mode someone else's deletion reads impersonally")
    func placeholderIsImpersonalForOthers() {
        let items = ChatItem.from(
            [deleted(1, them, deletedBy: them, after: 0)],
            selfUserID: me,
            deletedPresentation: .placeholder
        )
        #expect(messageRows(items).first?.content == .deleted("This message was deleted"))
    }

    @Test("A tombstone never anchors the delivery receipt, even when it is my newest row")
    func tombstoneDoesNotAnchorReceipt() {
        let items = ChatItem.from(
            [text(1, me, "hello", after: 0), deleted(2, me, deletedBy: me, after: 60)],
            selfUserID: me,
            deletedPresentation: .placeholder
        )
        let rows = messageRows(items)
        #expect(rows.count == 2)
        #expect(rows[0].receipt?.displayText == "Delivered")
        #expect(rows[1].receipt == nil)
    }

    @Test("An edited message is flagged for the edited marker")
    func editedMessageIsFlagged() {
        let plain = text(1, me, "after", after: 0)
        let edited = ConversationMessage(
            id: plain.id, senderID: plain.senderID, content: plain.content,
            date: plain.date, unreadSeq: plain.unreadSeq, eventSequence: 2,
            lastEditedTs: base.addingTimeInterval(30)
        )
        let items = ChatItem.from([edited], selfUserID: me)
        #expect(messageRows(items).first?.isEdited == true)
    }

    @Test("Actions come back in menu order, never in set order")
    func actionsAreOrdered() {
        let items = ChatItem.from(
            [text(1, me, "hi", after: 0)],
            selfUserID: me,
            capabilities: { _ in [.delete, .edit, .copy] }
        )
        #expect(messageRows(items).first?.actions == [.copy, .edit, .delete])
    }

    @Test("The default policy shows a placeholder, so a deleted row keeps its place")
    func defaultPolicyShowsPlaceholder() {
        #expect(MessagePolicy.default.deletedPresentation == .placeholder)

        let items = ChatItem.from(
            [text(1, them, "hi", after: 0), deleted(2, them, deletedBy: them, after: 30)],
            selfUserID: me,
            deletedPresentation: MessagePolicy.default.deletedPresentation
        )
        let rows = messageRows(items)
        #expect(rows.count == 2)
        #expect(rows[1].content == .deleted("This message was deleted"))
        #expect(rows[0].isContinuedByNext)
    }

    @Test("A group transcript flags every row, including a sender the roster cannot name")
    func attributionIsFlaggedPerTranscript() {
        let named = UUID()
        let items = ChatItem.from(
            [text(1, named, "hi", after: 0), text(2, them, "whoa", after: 30), text(3, me, "hey", after: 60)],
            selfUserID: me,
            author: { $0.senderID == named ? ChatAuthor(id: named, name: "KT") : nil },
            namesAuthors: true
        )
        let rows = messageRows(items)
        // The flag is the transcript's, so the unnamed row carries it too and keeps the gutter.
        #expect(rows.allSatisfy { $0.isAttributedTranscript })
        #expect(rows[0].author?.name == "KT")
        #expect(rows[1].author == nil)
    }

    @Test("A DM flags no row, so no bubble gives up a gutter")
    func directMessagesAreNotAttributed() {
        let items = ChatItem.from([text(1, them, "hi", after: 0)], selfUserID: me)
        #expect(messageRows(items).allSatisfy { !$0.isAttributedTranscript })
    }

    @Test("A bare emoji row breaks the bubble run on both sides and leaves attribution alone")
    func emojiRowSplitsBubbleRunFromAuthorRun() {
        let items = ChatItem.from([
            text(1, them, "hello", after: 0),
            text(2, them, "👍", after: 60),
            text(3, them, "there", after: 120),
        ], selfUserID: me)
        let rows = messageRows(items)

        // The author run is untouched — one run of three from the same sender.
        #expect(rows.map(\.isContinuationFromPrevious) == [false, true, true])
        #expect(rows.map(\.isContinuedByNext) == [true, true, false])

        // The bubble run is broken around the emoji row, on the row itself and on both neighbours.
        #expect(rows.map(\.joinsBubbleAbove) == [false, false, false])
        #expect(rows.map(\.joinsBubbleBelow) == [false, false, false])

        #expect(rows.map(\.isEmojiOnly) == [false, true, false])
        #expect(rows.map(\.rendersAsLargeEmoji) == [false, true, false])
    }

    @Test("Two adjacent bubbles still join")
    func bubbleRunSurvivesWithoutAnEmojiRow() {
        let items = ChatItem.from([text(1, me, "a", after: 0), text(2, me, "b", after: 60)], selfUserID: me)
        let rows = messageRows(items)
        #expect(rows[0].joinsBubbleBelow)
        #expect(rows[1].joinsBubbleAbove)
        #expect(rows[0].isContinuedByNext)
        #expect(rows[1].isContinuationFromPrevious)
    }

    @Test("An emoji reply keeps its bubble and its place in the bubble run")
    func emojiReplyKeepsBubble() {
        let items = ChatItem.from([
            text(1, them, "hello", after: 0),
            reply(2, them, "👍", to: 1, after: 60),
        ], selfUserID: me)
        let rows = messageRows(items)

        #expect(rows[1].isEmojiOnly)
        #expect(!rows[1].rendersAsLargeEmoji)
        #expect(rows[0].joinsBubbleBelow)
        #expect(rows[1].joinsBubbleAbove)
    }

    @Test("A cash row is never emoji-only")
    func cashRowIsNeverEmojiOnly() {
        let fiat = ExchangedFiat(
            nativeAmount: FiatAmount(value: 5, currency: .usd),
            rate: Rate(fx: 1, currency: .usd)
        )
        let items = ChatItem.from([
            ConversationMessage(id: MessageID(value: 1), senderID: me, content: .cash(fiat), date: base, unreadSeq: 1),
        ], selfUserID: me)
        let rows = messageRows(items)
        #expect(!rows[0].isEmojiOnly)
        #expect(!rows[0].rendersAsLargeEmoji)
    }

    @Test("A tombstone is never emoji-only, whatever it replaced")
    func tombstoneIsNeverEmojiOnly() {
        let items = ChatItem.from(
            [deleted(1, them, after: 0)],
            selfUserID: me,
            deletedPresentation: .placeholder
        )
        let rows = messageRows(items)
        #expect(!rows[0].isEmojiOnly)
        #expect(!rows[0].rendersAsLargeEmoji)
    }
}
