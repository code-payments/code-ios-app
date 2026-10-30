//
//  PinnedMessagesTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import FlipcashCore

@Suite("Pinned messages")
struct PinnedMessagesTests {

    private let pinner = UUID()

    private func message(_ id: UInt64, deleted: Bool = false) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id), senderID: pinner,
            content: deleted ? .deleted(.init(deletedBy: nil, deletedAt: Date(timeIntervalSince1970: 0))) : .text("m\(id)"),
            date: Date(timeIntervalSince1970: TimeInterval(id)), unreadSeq: 1, eventSequence: 1
        )
    }

    private func pin(_ id: UInt64, deleted: Bool = false, withMessage: Bool = true) -> ConversationPin {
        ConversationPin(
            messageID: MessageID(value: id), pinnedBy: pinner, pinnedAt: Date(timeIntervalSince1970: TimeInterval(id)),
            message: withMessage ? message(id, deleted: deleted) : nil
        )
    }

    private func summary(_ version: UInt64) -> ConversationPinSummary {
        ConversationPinSummary(latest: nil, count: 0, version: version)
    }

    private func ids(_ pins: [ConversationPin]) -> [UInt64] {
        pins.map(\.messageID.value)
    }

    // MARK: - PinsChanged versions

    @Test("The next version's pin goes to the front")
    func nextVersionPinApplies() {
        var list = PinnedMessages(pins: [pin(1)], version: 4)
        let outcome1 = list.apply(.pinned(pin(2)), summary: summary(5))

        #expect(outcome1 == .applied)
        #expect(ids(list.pins) == [2, 1])
        #expect(list.version == 5)
    }

    @Test("The next version's unpin removes the pin")
    func nextVersionUnpinApplies() {
        var list = PinnedMessages(pins: [pin(2), pin(1)], version: 4)
        let outcome2 = list.apply(.unpinned(MessageID(value: 2)), summary: summary(5))

        #expect(outcome2 == .applied)
        #expect(ids(list.pins) == [1])
    }

    @Test("A version the list already has, or an older one, is dropped")
    func staleVersionDropped() {
        var list = PinnedMessages(pins: [pin(1)], version: 4)
        let outcome3 = list.apply(.pinned(pin(2)), summary: summary(4))

        #expect(outcome3 == .stale)
        let outcome4 = list.apply(.unpinned(MessageID(value: 1)), summary: summary(3))

        #expect(outcome4 == .stale)
        #expect(ids(list.pins) == [1])
        #expect(list.version == 4)
    }

    @Test("A gap in versions asks for a refetch and leaves the list alone")
    func gapNeedsRefetch() {
        var list = PinnedMessages(pins: [pin(1)], version: 4)
        let outcome5 = list.apply(.pinned(pin(2)), summary: summary(6))

        #expect(outcome5 == .needsRefetch)
        #expect(ids(list.pins) == [1])
        #expect(list.version == 4)
    }

    @Test("A newer summary without its change asks for a refetch")
    func missingChangeNeedsRefetch() {
        var list = PinnedMessages(pins: [pin(1)], version: 4)
        let outcome6 = list.apply(nil, summary: summary(5))

        #expect(outcome6 == .needsRefetch)
    }

    @Test("A pin delivered without its message asks for a refetch")
    func pinWithoutMessageNeedsRefetch() {
        var list = PinnedMessages(pins: [], version: 0)
        let outcome7 = list.apply(.pinned(pin(2, withMessage: false)), summary: summary(1))

        #expect(outcome7 == .needsRefetch)
    }

    @Test("Re-pinning a pinned message moves it to the front instead of listing it twice")
    func repinMovesToFront() {
        var list = PinnedMessages(pins: [pin(2), pin(1)], version: 4)
        let outcome8 = list.apply(.pinned(pin(1)), summary: summary(5))

        #expect(outcome8 == .applied)
        #expect(ids(list.pins) == [1, 2])
    }

    // MARK: - Tombstones

    @Test("A deleted pinned message stays pinned but is not visible")
    func tombstoneHidden() {
        let list = PinnedMessages(pins: [pin(3, deleted: true), pin(2), pin(1, withMessage: false)], version: 1)
        #expect(ids(list.visible) == [2])
        #expect(list.messageIDs == [MessageID(value: 3), MessageID(value: 2), MessageID(value: 1)])
    }

    @Test("When the latest pin is a tombstone the bar shows the next one")
    func shownSkipsTombstone() {
        let list = PinnedMessages(pins: [pin(3, deleted: true), pin(2), pin(1)], version: 1)
        #expect(list.shown(nil)?.messageID.value == 2)
        #expect(list.shown(MessageID(value: 3))?.messageID.value == 2)
    }

    @Test("A message deleted after the fetch drops out of the visible pins")
    func replaceWithTombstone() {
        var list = PinnedMessages(pins: [pin(2), pin(1)], version: 1)
        let outcome9 = list.replace(message(2, deleted: true))

        #expect(outcome9)
        #expect(ids(list.visible) == [1])
        let replacedMissing = list.replace(message(9, deleted: true))
        #expect(!replacedMissing)
    }

    // MARK: - Stepping

    @Test("Stepping walks to older pins, skips tombstones, and wraps to the newest")
    func stepping() {
        let list = PinnedMessages(pins: [pin(4), pin(3, deleted: true), pin(2), pin(1)], version: 1)
        #expect(list.pin(after: nil)?.messageID.value == 4)
        #expect(list.pin(after: MessageID(value: 4))?.messageID.value == 2)
        #expect(list.pin(after: MessageID(value: 2))?.messageID.value == 1)
        #expect(list.pin(after: MessageID(value: 1))?.messageID.value == 4)
    }

    @Test("Nothing to show or step to when every pin is a tombstone")
    func allTombstones() {
        let list = PinnedMessages(pins: [pin(1, deleted: true)], version: 1)
        #expect(list.shown(nil) == nil)
        #expect(list.pin(after: nil) == nil)
    }
}
