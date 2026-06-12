//
//  ConversationTranscriptTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite("Conversation transcript items")
struct ConversationTranscriptItemTests {

    private static let selfID = UUID()
    private static let otherID = UUID()
    private static let epoch = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private static func message(
        id: UInt64,
        from senderID: UUID,
        minutesAfterEpoch minutes: Double
    ) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id),
            senderID: senderID,
            content: .text("message-\(id)"),
            date: epoch.addingTimeInterval(minutes * 60),
            unreadSeq: 0
        )
    }

    private static func positions(of items: [ConversationTranscriptItem]) -> [ConversationTranscriptItem.Position] {
        items.compactMap {
            switch $0 {
            case .separator: nil
            case .message(_, let position): position
            }
        }
    }

    private static func separatorCount(of items: [ConversationTranscriptItem]) -> Int {
        items.count { if case .separator = $0 { true } else { false } }
    }

    @Test("Empty transcript produces no items")
    func items_empty_returnsEmpty() {
        let items = ConversationTranscriptItem.items(from: [], selfUserID: Self.selfID)
        #expect(items.isEmpty)
    }

    @Test("First message gets a date separator")
    func items_firstMessage_showsSeparator() {
        let items = ConversationTranscriptItem.items(
            from: [Self.message(id: 1, from: Self.selfID, minutesAfterEpoch: 0)],
            selfUserID: Self.selfID
        )
        #expect(Self.separatorCount(of: items) == 1)
        guard case .separator = items.first else {
            Issue.record("Expected a leading separator")
            return
        }
    }

    @Test("Sender change does not insert a separator")
    func items_senderChange_noSeparator() {
        let items = ConversationTranscriptItem.items(
            from: [
                Self.message(id: 1, from: Self.selfID, minutesAfterEpoch: 0),
                Self.message(id: 2, from: Self.otherID, minutesAfterEpoch: 1),
            ],
            selfUserID: Self.selfID
        )
        #expect(Self.separatorCount(of: items) == 1)
    }

    @Test("A gap over 15 minutes inserts a separator and breaks grouping")
    func items_timeGap_insertsSeparatorAndBreaksGrouping() {
        let items = ConversationTranscriptItem.items(
            from: [
                Self.message(id: 1, from: Self.selfID, minutesAfterEpoch: 0),
                Self.message(id: 2, from: Self.selfID, minutesAfterEpoch: 16),
            ],
            selfUserID: Self.selfID
        )
        #expect(Self.separatorCount(of: items) == 2)

        let positions = Self.positions(of: items)
        #expect(positions[0].groupedBelow == false)
        #expect(positions[1].groupedAbove == false)
    }

    @Test("Same-sender run groups its middle message on both edges")
    func items_sameSenderRun_groupsMiddleBothEdges() {
        let items = ConversationTranscriptItem.items(
            from: [
                Self.message(id: 1, from: Self.selfID, minutesAfterEpoch: 0),
                Self.message(id: 2, from: Self.selfID, minutesAfterEpoch: 1),
                Self.message(id: 3, from: Self.selfID, minutesAfterEpoch: 2),
            ],
            selfUserID: Self.selfID
        )
        let positions = Self.positions(of: items)
        #expect(positions[0].groupedAbove == false)
        #expect(positions[0].groupedBelow == true)
        #expect(positions[1].groupedAbove == true)
        #expect(positions[1].groupedBelow == true)
        #expect(positions[2].groupedAbove == true)
        #expect(positions[2].groupedBelow == false)
    }

    @Test("Sender change breaks grouping on the shared edge")
    func items_senderChange_breaksGrouping() {
        let items = ConversationTranscriptItem.items(
            from: [
                Self.message(id: 1, from: Self.selfID, minutesAfterEpoch: 0),
                Self.message(id: 2, from: Self.otherID, minutesAfterEpoch: 1),
            ],
            selfUserID: Self.selfID
        )
        let positions = Self.positions(of: items)
        #expect(positions[0].groupedBelow == false)
        #expect(positions[1].groupedAbove == false)
        #expect(positions[0].isFromSelf == true)
        #expect(positions[1].isFromSelf == false)
    }

    @Test("Only the latest own message is marked for the Delivered receipt")
    func items_latestFromSelf_marksOnlyNewestOwnMessage() {
        let items = ConversationTranscriptItem.items(
            from: [
                Self.message(id: 1, from: Self.selfID, minutesAfterEpoch: 0),
                Self.message(id: 2, from: Self.selfID, minutesAfterEpoch: 1),
                Self.message(id: 3, from: Self.otherID, minutesAfterEpoch: 2),
            ],
            selfUserID: Self.selfID
        )
        let positions = Self.positions(of: items)
        #expect(positions.map(\.isLatestFromSelf) == [false, true, false])
    }
}

@Suite("Conversation bubble corner radii")
struct ConversationBubbleStyleTests {

    @Test("A lone bubble is uniformly rounded")
    func cornerRadii_lone_uniform() {
        let radii = ConversationBubbleStyle.cornerRadii(isFromSelf: true, groupedAbove: false, groupedBelow: false)
        #expect(radii.topLeading == ConversationBubbleStyle.baseRadius)
        #expect(radii.topTrailing == ConversationBubbleStyle.baseRadius)
        #expect(radii.bottomLeading == ConversationBubbleStyle.baseRadius)
        #expect(radii.bottomTrailing == ConversationBubbleStyle.baseRadius)
    }

    @Test("A sent bubble tightens only its trailing edge when grouped")
    func cornerRadii_sentGrouped_tightensTrailingEdge() {
        let radii = ConversationBubbleStyle.cornerRadii(isFromSelf: true, groupedAbove: true, groupedBelow: true)
        #expect(radii.topLeading == ConversationBubbleStyle.baseRadius)
        #expect(radii.bottomLeading == ConversationBubbleStyle.baseRadius)
        #expect(radii.topTrailing == ConversationBubbleStyle.groupedRadius)
        #expect(radii.bottomTrailing == ConversationBubbleStyle.groupedRadius)
    }

    @Test("A received bubble tightens only its leading edge when grouped")
    func cornerRadii_receivedGrouped_tightensLeadingEdge() {
        let radii = ConversationBubbleStyle.cornerRadii(isFromSelf: false, groupedAbove: true, groupedBelow: true)
        #expect(radii.topLeading == ConversationBubbleStyle.groupedRadius)
        #expect(radii.bottomLeading == ConversationBubbleStyle.groupedRadius)
        #expect(radii.topTrailing == ConversationBubbleStyle.baseRadius)
        #expect(radii.bottomTrailing == ConversationBubbleStyle.baseRadius)
    }

    @Test("Grouping above tightens only the top corner of the aligned edge")
    func cornerRadii_groupedAboveOnly_tightensTopOnly() {
        let radii = ConversationBubbleStyle.cornerRadii(isFromSelf: true, groupedAbove: true, groupedBelow: false)
        #expect(radii.topTrailing == ConversationBubbleStyle.groupedRadius)
        #expect(radii.bottomTrailing == ConversationBubbleStyle.baseRadius)
    }
}
