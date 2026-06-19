//
//  ChatBubbleViewTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
@testable import FlipcashUI

@MainActor
@Suite("Bubble corner grouping")
struct ChatBubbleViewCornerTests {

    private let base = BubbleBackgroundView.baseRadius     // 12
    private let grouped = BubbleBackgroundView.groupedRadius // 6

    @Test("A standalone bubble uses the base radius on all four corners")
    func standalone_allBase() {
        let c = BubbleBackgroundView.corners(isFromSelf: true, groupedAbove: false, groupedBelow: false)
        #expect(c == BubbleBackgroundView.Corners(topLeft: base, topRight: base, bottomLeft: base, bottomRight: base))
    }

    @Test("A self bubble continued below flattens only its inner (right) bottom corner")
    func selfContinuedBelow_flattensInnerBottom() {
        let c = BubbleBackgroundView.corners(isFromSelf: true, groupedAbove: false, groupedBelow: true)
        #expect(c.bottomRight == grouped) // inner bottom flattened
        #expect(c.bottomLeft == base)     // outer bottom kept
        #expect(c.topRight == base)       // top untouched
    }

    @Test("An other bubble continued from above flattens only its inner (left) top corner")
    func otherContinuedAbove_flattensInnerTop() {
        let c = BubbleBackgroundView.corners(isFromSelf: false, groupedAbove: true, groupedBelow: false)
        #expect(c.topLeft == grouped) // inner top flattened
        #expect(c.topRight == base)   // outer top kept
        #expect(c.bottomLeft == base) // bottom untouched
    }

    @Test("A middle bubble in a self run flattens both inner (right) corners")
    func selfMiddleOfRun_flattensBothInner() {
        let c = BubbleBackgroundView.corners(isFromSelf: true, groupedAbove: true, groupedBelow: true)
        #expect(c.topRight == grouped)
        #expect(c.bottomRight == grouped)
        #expect(c.topLeft == base)    // outer kept
        #expect(c.bottomLeft == base)
    }
}

@MainActor
@Suite("ChatMessageCell alignment")
struct ChatMessageCellAlignmentTests {

    private func laidOutCell(sender: ChatMessage.Sender) -> (cell: ChatMessageCell, bubble: UIView) {
        let cell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 320, height: 80))
        cell.configure(with: ChatMessage(id: "1", text: "hi", sender: sender), maxWidth: 250)
        cell.layoutIfNeeded()
        return (cell, cell.contentView.subviews[0])
    }

    @Test("A self message hugs the trailing edge")
    func selfMessage_hugsTrailing() {
        let (cell, bubble) = laidOutCell(sender: .me)
        #expect(abs(bubble.frame.maxX - (cell.contentView.bounds.width - 12)) < 0.5)
        #expect(bubble.frame.minX > 12) // does not span the full width
    }

    @Test("An other message hugs the leading edge")
    func otherMessage_hugsLeading() {
        let (cell, bubble) = laidOutCell(sender: .other)
        #expect(abs(bubble.frame.minX - 12) < 0.5)
        #expect(bubble.frame.maxX < cell.contentView.bounds.width - 12)
    }
}
