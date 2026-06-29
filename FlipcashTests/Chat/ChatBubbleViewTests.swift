//
//  ChatBubbleViewTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import SwiftUI
import FlipcashCore
@testable import FlipcashUI

@MainActor
@Suite("Bubble corner grouping")
struct ChatBubbleViewCornerTests {

    private let base = BubbleBackgroundView.baseRadius      // 12
    private let grouped = BubbleBackgroundView.groupedRadius // 6

    @Test("A standalone bubble uses the base radius on all four corners")
    func standalone_allBase() {
        let r = BubbleBackgroundView.radii(isFromSelf: true, groupedAbove: false, groupedBelow: false)
        #expect(r == RectangleCornerRadii(topLeading: base, bottomLeading: base, bottomTrailing: base, topTrailing: base))
    }

    @Test("A self bubble continued below flattens only its inner (trailing) bottom corner")
    func selfContinuedBelow_flattensInnerBottom() {
        let r = BubbleBackgroundView.radii(isFromSelf: true, groupedAbove: false, groupedBelow: true)
        #expect(r.bottomTrailing == grouped) // inner bottom flattened to 6
        #expect(r.bottomLeading == base)     // outer kept
        #expect(r.topTrailing == base)       // top untouched
    }

    @Test("An other bubble continued from above flattens only its inner (leading) top corner")
    func otherContinuedAbove_flattensInnerTop() {
        let r = BubbleBackgroundView.radii(isFromSelf: false, groupedAbove: true, groupedBelow: false)
        #expect(r.topLeading == grouped) // inner top flattened to 6
        #expect(r.topTrailing == base)   // outer kept
        #expect(r.bottomLeading == base) // bottom untouched
    }

    @Test("A middle bubble in a self run flattens both inner (trailing) corners")
    func selfMiddleOfRun_flattensBothInner() {
        let r = BubbleBackgroundView.radii(isFromSelf: true, groupedAbove: true, groupedBelow: true)
        #expect(r.topTrailing == grouped)
        #expect(r.bottomTrailing == grouped)
        #expect(r.topLeading == base)    // outer kept
        #expect(r.bottomLeading == base)
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
