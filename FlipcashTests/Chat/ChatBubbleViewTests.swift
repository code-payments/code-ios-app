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
    private let grouped = BubbleBackgroundView.groupedRadius // 4

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

    /// Returns the bubble's frame *in the content view's* coordinate space. `contentView.subviews[0]`
    /// is the column stack view, which spans the whole row by design and hugs the sender's edge
    /// through its `alignment` — so measuring that against the content view's edges asserts nothing.
    private func laidOutCell(sender: ChatMessage.Sender) -> (cell: ChatMessageCell, bubble: CGRect) {
        let cell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 320, height: 80))
        cell.configure(with: ChatMessage(id: "1", text: "hi", sender: sender), maxWidth: 250)
        cell.layoutIfNeeded()
        let bubble = cell.bubbleView
        return (cell, bubble.convert(bubble.bounds, to: cell.contentView))
    }

    @Test("A self message hugs the trailing edge")
    func selfMessage_hugsTrailing() {
        let (cell, bubble) = laidOutCell(sender: .me)
        #expect(abs(bubble.maxX - (cell.contentView.bounds.width - 12)) < 0.5)
        #expect(bubble.minX > 12) // does not span the full width
    }

    @Test("An other message hugs the leading edge")
    func otherMessage_hugsLeading() {
        let (cell, bubble) = laidOutCell(sender: .other)
        #expect(abs(bubble.minX - 12) < 0.5)
        #expect(bubble.maxX < cell.contentView.bounds.width - 12)
    }
}

@MainActor
@Suite("Chat bubble deleted and edited rendering")
struct ChatBubbleDeletedTests {

    @Test("A deleted bubble shows the tombstone copy")
    func deletedBubbleShowsCopy() {
        let text = ChatBubbleView.displayText(
            for: ChatMessage(id: "1", content: .deleted("You deleted this message"), sender: .me)
        )
        #expect(text?.string == "You deleted this message")
    }

    @Test("An edited bubble reserves the marker's width after the body, drawn clear")
    func editedBubbleReservesMarker() {
        let text = ChatBubbleView.displayText(
            for: ChatMessage(id: "1", content: .text("hello"), sender: .me, isEdited: true)
        )
        #expect(text?.string == "hello  Edited")

        // The reservation holds the space; the visible marker is the corner label, so the run in
        // the body must not draw.
        let markerColor = text?.attribute(.foregroundColor, at: 7, effectiveRange: nil) as? UIColor
        #expect(markerColor == UIColor.clear)
    }

    @Test("Only a message with a body left to revise carries the marker")
    func markerIsForRevisableBodies() {
        #expect(ChatBubbleView.showsEditedMarker(
            for: ChatMessage(id: "1", content: .text("hello"), sender: .me, isEdited: true)
        ))
        #expect(!ChatBubbleView.showsEditedMarker(
            for: ChatMessage(id: "1", content: .text("hello"), sender: .me)
        ))
        #expect(!ChatBubbleView.showsEditedMarker(
            for: ChatMessage(id: "1", content: .deleted("You deleted this message"), sender: .me, isEdited: true)
        ))
    }

    private static let maxWidth: CGFloat = 250

    /// A bubble laid out through the real cell, so the width cap and self-sizing apply. The cell is
    /// measured the way the collection view measures it — a fixed frame height would stretch the
    /// bubble to fill it and hide the wrap.
    private func laidOutBubble(text: String, isEdited: Bool) -> ChatBubbleView {
        let cell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 320, height: 80))
        cell.configure(
            with: ChatMessage(id: "1", content: .text(text), sender: .me, isEdited: isEdited),
            maxWidth: Self.maxWidth
        )
        let fitted = cell.contentView.systemLayoutSizeFitting(
            CGSize(width: 320, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        cell.frame = CGRect(x: 0, y: 0, width: 320, height: fitted.height)
        cell.layoutIfNeeded()
        return cell.bubbleView
    }

    private func marker(in bubble: ChatBubbleView) -> UILabel? {
        bubble.subviews.compactMap { $0 as? UILabel }.first { $0.text == EditedMarker.text }
    }

    @Test("The marker sits in the bubble's bottom-trailing corner")
    func markerSitsInTheCorner() throws {
        let bubble = laidOutBubble(text: "hello", isEdited: true)
        let marker = try #require(marker(in: bubble))

        #expect(!marker.isHidden)
        #expect(abs(marker.frame.maxX - (bubble.bounds.width - EditedMarker.trailingInset)) < 0.5)
        #expect(abs(marker.frame.maxY - (bubble.bounds.height - 9)) < 0.5)
    }

    @Test("A last line with room keeps the marker on it, widening the bubble")
    func markerStaysOnALastLineWithRoom() {
        let plain = laidOutBubble(text: "hello", isEdited: false)
        let edited = laidOutBubble(text: "hello", isEdited: true)

        #expect(abs(edited.bounds.height - plain.bounds.height) < 0.5) // still one line
        #expect(edited.bounds.width > plain.bounds.width)              // grew to hold the marker
    }

    @Test("A last line with no room drops the marker onto a line of its own")
    func markerWrapsOffAFullLastLine() throws {
        // Pack short words onto one line until one more would wrap it, so the leftover room on that
        // line is narrower than a word — and narrower still than the marker. Measured off the
        // laid-out bubble rather than off the font, so the insets and the width cap are the real
        // ones.
        let oneLine = laidOutBubble(text: "w", isEdited: false).bounds.height
        var body = "w"
        while laidOutBubble(text: body + " w", isEdited: false).bounds.height == oneLine { body += " w" }

        let plain = laidOutBubble(text: body, isEdited: false)
        let edited = laidOutBubble(text: body, isEdited: true)
        let marker = try #require(marker(in: edited))

        #expect(abs(plain.bounds.height - oneLine) < 0.5)   // the body itself still fits one line
        #expect(edited.bounds.height > plain.bounds.height) // the marker took a line of its own
        #expect(abs(marker.frame.maxX - (edited.bounds.width - EditedMarker.trailingInset)) < 0.5)
    }

    @Test("An unedited bubble is just its body")
    func uneditedBubbleIsPlain() {
        let text = ChatBubbleView.displayText(
            for: ChatMessage(id: "1", content: .text("hello"), sender: .me)
        )
        #expect(text?.string == "hello")
    }

    @Test("A cash row has no bubble text — it uses its own cell")
    func cashRowHasNoBubbleText() {
        let cash = ChatCashContent(amount: "$5.00", token: "Cash", flagImageName: nil, iconURL: nil, isTip: false)
        #expect(ChatBubbleView.displayText(for: ChatMessage(id: "1", content: .cash(cash), sender: .me)) == nil)
    }

    @Test("A deleted message reuses the plain text cell, so a delete reconfigures in place")
    func deletedReusesTextCell() {
        let deleted = ChatItem.message(ChatMessage(id: "1", content: .deleted("Message deleted"), sender: .other))
        let plain = ChatItem.message(ChatMessage(id: "1", text: "hi", sender: .other))
        #expect(deleted.differenceIdentifier == plain.differenceIdentifier)
    }
}
