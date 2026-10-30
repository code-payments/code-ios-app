//
//  ConversationPinsTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Conversation pins")
struct ConversationPinsTests {

    private let selfUserID = UUID()
    private let chat = ConversationID(data: Data(repeating: 0x5A, count: 32))

    private func message(_ id: UInt64, deleted: Bool = false) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id), senderID: selfUserID,
            content: deleted ? .deleted(.init(deletedBy: nil, deletedAt: .now)) : .text("m\(id)"),
            date: Date(timeIntervalSince1970: TimeInterval(id)), unreadSeq: 1, eventSequence: 1
        )
    }

    private func pin(_ id: UInt64) -> ConversationPin {
        ConversationPin(messageID: MessageID(value: id), pinnedBy: selfUserID, pinnedAt: .now, message: message(id))
    }

    private func summary(_ version: UInt64, latest: ConversationPin? = nil) -> ConversationPinSummary {
        ConversationPinSummary(latest: latest, count: 0, version: version)
    }

    private func loaded(_ pins: [ConversationPin], version: UInt64) async -> (ConversationPins, MockConversations) {
        let messaging = MockConversations()
        messaging.pinsPage = ConversationPinsPage(pins: pins, summary: summary(version), pagingToken: Data(), hasMore: false)
        let unit = ConversationPins(messaging: messaging, owner: .generate()!, selfUserID: selfUserID)
        await unit.load(chat)
        return (unit, messaging)
    }

    private func ids(_ pins: [ConversationPin]) -> [UInt64] {
        pins.map(\.messageID.value)
    }

    @Test("Opening a chat fetches its pins")
    func loadFetches() async {
        let (unit, messaging) = await loaded([pin(2), pin(1)], version: 3)
        #expect(ids(unit.visible(in: chat)) == [2, 1])
        #expect(unit.list(in: chat)?.version == 3)
        #expect(messaging.pinnedFetchCount == 1)
    }

    @Test("The next PinsChanged version applies; an older one is dropped")
    func pinsChangedVersions() async {
        let (unit, _) = await loaded([pin(1)], version: 3)
        unit.apply(.pinsChanged(conversationID: chat, change: .pinned(pin(2)), summary: summary(4)))
        #expect(ids(unit.visible(in: chat)) == [2, 1])
        unit.apply(.pinsChanged(conversationID: chat, change: .unpinned(MessageID(value: 2)), summary: summary(4)))
        #expect(ids(unit.visible(in: chat)) == [2, 1])
    }

    @Test("A chat read without a pin summary never clears the pins")
    func missingSummaryKeepsPins() async {
        let (unit, messaging) = await loaded([pin(1)], version: 3)
        let read = Conversation(id: chat, members: [], lastMessage: nil, lastActivity: .now, pinSummary: nil)
        unit.apply(.metadataRefresh(read))
        #expect(ids(unit.visible(in: chat)) == [1])
        #expect(messaging.pinnedFetchCount == 1)
    }

    @Test("A pinned message deleted later drops off the bar and the next pin shows")
    func deletedPinDropsOff() async {
        let (unit, _) = await loaded([pin(2), pin(1)], version: 3)
        #expect(unit.barPin(in: chat)?.messageID.value == 2)
        unit.apply(.chatEvents(conversationID: chat, events: [
            DecodedChatEvent(sequence: 9, count: 1, mutations: [.deleted(message(2, deleted: true))]),
        ]))
        #expect(unit.barPin(in: chat)?.messageID.value == 1)
        #expect(unit.pinnedIDs(in: chat).contains(MessageID(value: 2)))
    }

    @Test("Each bar tap steps to the next older pin, then wraps")
    func barSteps() async {
        let (unit, _) = await loaded([pin(3), pin(2), pin(1)], version: 3)
        #expect(unit.barPin(in: chat)?.messageID.value == 3)
        unit.advanceBar(in: chat)
        #expect(unit.barPin(in: chat)?.messageID.value == 2)
        unit.advanceBar(in: chat)
        unit.advanceBar(in: chat)
        #expect(unit.barPin(in: chat)?.messageID.value == 3)
    }

    @Test("A new pin takes the bar back to the newest")
    func newPinResetsBar() async {
        let (unit, _) = await loaded([pin(2), pin(1)], version: 3)
        unit.advanceBar(in: chat)
        #expect(unit.barPin(in: chat)?.messageID.value == 1)
        unit.apply(.pinsChanged(conversationID: chat, change: .pinned(pin(3)), summary: summary(4)))
        #expect(unit.barPin(in: chat)?.messageID.value == 3)
    }

    @Test("A pin at the cap is held until an unpin frees a slot")
    func tooManyPinsHoldsPending() async {
        let (unit, messaging) = await loaded([pin(1)], version: 3)
        messaging.pinError = ErrorPinMessage.tooManyPins
        let outcome = await unit.pin(message(7), in: chat)
        #expect(outcome == .full)
        #expect(unit.pendingPin == .init(conversationID: chat, messageID: MessageID(value: 7)))

        messaging.pinError = nil
        messaging.pinSummaryResponse = summary(4)
        #expect(await unit.unpin(MessageID(value: 1), in: chat))
        messaging.pinSummaryResponse = summary(5, latest: pin(7))
        let retried = await unit.pin(message(7), in: chat)
        #expect(retried == .pinned)
        #expect(unit.pendingPin == nil)
        #expect(ids(unit.visible(in: chat)) == [7])
    }

    @Test("Pinning and unpinning tell the transcript to re-read its menus")
    func changesNotify() async {
        let (unit, messaging) = await loaded([], version: 0)
        var changes = 0
        unit.didChange = { changes += 1 }
        messaging.pinSummaryResponse = summary(1, latest: pin(4))
        _ = await unit.pin(message(4), in: chat)
        #expect(unit.pinnedIDs(in: chat) == [MessageID(value: 4)])
        messaging.pinSummaryResponse = summary(2)
        _ = await unit.unpin(MessageID(value: 4), in: chat)
        #expect(unit.pinnedIDs(in: chat).isEmpty)
        #expect(changes == 2)
    }
}

@MainActor
@Suite("Pin slot")
struct PinSlotTests {

    @Test("Without pins nothing shows")
    func noPins() {
        #expect(PinSlot.resolve(hasPins: false, deckStyle: .strip) == .none)
        #expect(PinSlot.resolve(hasPins: false, deckStyle: nil) == .none)
    }

    @Test("Without requests the pins take the bar")
    func noRequests() {
        #expect(PinSlot.resolve(hasPins: true, deckStyle: nil) == .bar)
    }

    @Test("C6: while the owed strip is out, the pins are a toolbar button")
    func stripOut() {
        #expect(PinSlot.resolve(hasPins: true, deckStyle: .strip) == .toolbarButton)
    }

    @Test("C6b: once the strip is the pill, the pins take the bar")
    func stripCollapsed() {
        #expect(PinSlot.resolve(hasPins: true, deckStyle: .pill) == .bar)
    }

    @Test("C7: a swipe past halfway docks the strip, and the pins take the bar")
    func dockPastHalfway() {
        let collapse = PaymentRequestStripCollapse()
        collapse.dock(following: 0.3)
        #expect(collapse.progress == 0.3)
        collapse.endDock(at: 0.6)
        #expect(collapse.isPinned)
        let style = PaymentRequestDeckStyle.collapsed(owes: true, isScrolledAway: collapse.isScrolledAway)
        #expect(PinSlot.resolve(hasPins: true, deckStyle: style) == .bar)
    }

    @Test("C7: a swipe short of halfway snaps the strip back")
    func dockSnapsBack() {
        let collapse = PaymentRequestStripCollapse()
        collapse.dock(following: 0.45)
        collapse.endDock(at: 0.45)
        #expect(collapse.progress == 0)
        #expect(!collapse.isPinned)
        let style = PaymentRequestDeckStyle.collapsed(owes: true, isScrolledAway: collapse.isScrolledAway)
        #expect(PinSlot.resolve(hasPins: true, deckStyle: style) == .toolbarButton)
    }

    @Test("C7: the dock outlasts scrolling back to the newest; a new request brings the strip back")
    func dockLastsUntilNewRequest() {
        let collapse = PaymentRequestStripCollapse()
        collapse.endDock(at: 0.8)
        collapse.update(distanceFromNewest: 0)
        #expect(collapse.isScrolledAway)
        collapse.unpin()
        #expect(!collapse.isScrolledAway)
        let style = PaymentRequestDeckStyle.collapsed(owes: true, isScrolledAway: collapse.isScrolledAway)
        #expect(PinSlot.resolve(hasPins: true, deckStyle: style) == .toolbarButton)
    }
}

@MainActor
@Suite("Pin bar")
struct PinBarTests {

    private let me = UUID()

    private func quote(_ content: ConversationMessage.Content, from senderID: UUID = UUID()) -> ChatQuote {
        let message = ConversationMessage(
            id: MessageID(value: 1),
            senderID: senderID,
            content: content,
            date: .now,
            unreadSeq: 1,
            eventSequence: 1
        )
        return ChatItem.pinQuote(
            of: message,
            selfUserID: me,
            authorName: "Maya",
            cashBranding: { _ in ("Cash", nil) },
            viewerAmount: { $0.nativeAmount }
        )
    }

    private func snippet(_ content: ConversationMessage.Content) -> String {
        quote(content).snippet
    }

    @Test("A text pin reads as its text")
    func textSnippet() {
        #expect(snippet(.text("dinner at 7?")) == "dinner at 7?")
    }

    @Test("A pin this device can't open reads as an encrypted message")
    func sealedSnippet() {
        #expect(snippet(.encrypted(scheme: 1, nonce: Data(), ciphertext: Data())) == "Encrypted message")
    }

    @Test("A pin names its sender, and the viewer as You")
    func pinAuthor() {
        #expect(quote(.text("hi")).authorName == "Maya")
        #expect(quote(.text("hi"), from: me).authorName == "You")
    }

    @Test("A photo pin carries its thumbnail, as a reply's quote does")
    func photoPinThumbnail() {
        let blobID = BlobID(data: Data([9, 8, 7]))
        let attachment = MediaAttachment(blobID: blobID, width: 300, height: 400, blurhash: "LEHV6nWB2yk8")
        #expect(quote(.media([attachment], caption: nil)).kind == .media(thumbnailBlobID: blobID, sealed: nil))
    }

    @Test("Only an upward drag on the strip carries it toward the pill")
    func dockFollowsUpwardDragOnly() {
        #expect(PaymentRequestPill.dockFraction(40) == 0)
        #expect(PaymentRequestPill.dockFraction(-PaymentRequestStripCollapse.distance / 2) == 0.5)
    }
}

@Suite("Pin bar segments")
@MainActor
struct PinBarSegmentsTests {

    /// The window and lit pin at each tap, starting from the newest: (visible bottom-to-top, lit).
    private func steps(count: Int) -> [PinBarSegments?] {
        (0..<count).map { PinBarSegments(count: count, index: $0) }
    }

    @Test("One pin keeps a single rule, no segments")
    func onePin() {
        #expect(PinBarSegments(count: 1, index: 0) == nil)
    }

    @Test("Two pins show both segments from the start, newest at the bottom")
    func twoPins() {
        let s = steps(count: 2)
        #expect(s[0]?.visible == [0, 1]); #expect(s[0]?.lit == 0)
        #expect(s[1]?.visible == [0, 1]); #expect(s[1]?.lit == 1)
    }

    @Test("Three pins: the track scrolls to keep the lit segment in the two-segment window")
    func threePins() {
        let s = steps(count: 3)
        #expect(s[0]?.visible == [0, 1]); #expect(s[0]?.lit == 0)
        // Figma Cycling (13016:87): pin 2 of 3 lit, pin 3 scrolled out above.
        #expect(s[1]?.visible == [0, 1]); #expect(s[1]?.lit == 1)
        #expect(s[2]?.visible == [1, 2]); #expect(s[2]?.lit == 2)
    }

    @Test("Five pins: each tap moves the lit segment up and the window follows it")
    func fivePins() {
        let s = steps(count: 5)
        #expect(s.map { $0?.visible } == [[0, 1], [0, 1], [1, 2], [2, 3], [3, 4]])
        #expect(s.map { $0?.lit } == [0, 1, 2, 3, 4])
        #expect(s.allSatisfy { $0.map { $0.visible.contains($0.lit) } ?? false })
    }
}
