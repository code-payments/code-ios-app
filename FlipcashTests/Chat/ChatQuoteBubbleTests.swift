//
//  ChatQuoteBubbleTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI

@Suite("Reply bubble quote panel")
@MainActor
struct ChatQuoteBubbleTests {

    private static let maxWidth: CGFloat = 250

    private let quote = ChatQuote(stableID: "7", authorName: "Ada", snippet: "dinner at 7?", kind: .text)

    private func laidOutCell(quote: ChatQuote?) -> ChatMessageCell {
        let cell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 320, height: 80))
        cell.configure(
            with: ChatMessage(id: "1", content: .text("works"), sender: .me, quote: quote),
            maxWidth: Self.maxWidth
        )
        let fitted = cell.contentView.systemLayoutSizeFitting(
            CGSize(width: 320, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        cell.frame = CGRect(x: 0, y: 0, width: 320, height: fitted.height)
        cell.layoutIfNeeded()
        return cell
    }

    @Test("A quote makes the bubble taller")
    func quote_growsTheBubble() {
        let plain = laidOutCell(quote: nil).bubbleView.frame.height
        let quoted = laidOutCell(quote: quote).bubbleView.frame.height
        #expect(quoted > plain)
    }

    @Test("A message with no quote reserves no height for the panel")
    func noQuote_reservesNothing() {
        let bubble = laidOutCell(quote: nil).bubbleView
        #expect(bubble.quotePanel.isHidden)
        #expect(bubble.quotePanel.frame.height == 0)
    }

    @Test("Reusing a bubble drops the previous quote")
    func reuse_dropsTheQuote() {
        let cell = laidOutCell(quote: quote)
        cell.configure(with: ChatMessage(id: "2", content: .text("hi"), sender: .me), maxWidth: Self.maxWidth)
        cell.layoutIfNeeded()
        #expect(cell.bubbleView.quotePanel.isHidden)
    }

    @Test("The panel reports the row it jumps to")
    func panel_reportsItsTarget() {
        var tapped: String?
        let cell = laidOutCell(quote: quote)
        cell.bubbleView.onQuoteTap = { tapped = $0 }
        cell.bubbleView.quotePanel.simulateTap()
        #expect(tapped == "7")
    }

    @Test("An unavailable quote is not tappable")
    func unavailableQuote_doesNotJump() {
        var tapped: String?
        let unavailable = ChatQuote(
            stableID: nil, authorName: "", snippet: ChatQuote.unavailableSnippet, kind: .unavailable
        )
        let cell = laidOutCell(quote: unavailable)
        cell.bubbleView.onQuoteTap = { tapped = $0 }
        cell.bubbleView.quotePanel.simulateTap()
        #expect(tapped == nil)
    }
}

@Suite("Reply bubble geometry")
@MainActor
struct ChatQuoteBubbleGeometryTests {

    private static let maxWidth: CGFloat = 250

    private let shortQuote = ChatQuote(stableID: "7", authorName: "Ada", snippet: "ok", kind: .text)
    private let longQuote = ChatQuote(
        stableID: "7",
        authorName: "Ada",
        snippet: String(repeating: "long enough to wrap ", count: 6),
        kind: .text
    )

    /// Lays out a real cell and returns the bubble's frame *in the content view's* coordinate
    /// space. The bubble sits inside the column stack view, so its own `frame` is relative to that
    /// stack — comparing it against the content view's edges without converting measures the wrong
    /// box, which is what makes the assertions below meaningful.
    private func laidOutCell(
        sender: ChatMessage.Sender,
        quote: ChatQuote?,
        text: String = "works"
    ) -> (cell: ChatMessageCell, bubbleFrame: CGRect) {
        let cell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 320, height: 80))
        cell.configure(
            with: ChatMessage(id: "1", content: .text(text), sender: sender, quote: quote),
            maxWidth: Self.maxWidth
        )
        let fitted = cell.contentView.systemLayoutSizeFitting(
            CGSize(width: 320, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        cell.frame = CGRect(x: 0, y: 0, width: 320, height: fitted.height)
        cell.layoutIfNeeded()
        let bubble = cell.bubbleView
        return (cell, bubble.convert(bubble.bounds, to: cell.contentView))
    }

    @Test("A quoted reply from me still hugs the trailing edge")
    func selfReply_hugsTrailing() {
        let (cell, bubble) = laidOutCell(sender: .me, quote: shortQuote)
        #expect(abs(bubble.maxX - (cell.contentView.bounds.width - 12)) < 0.5)
        #expect(bubble.minX > 12)
    }

    @Test("A quoted reply from them still hugs the leading edge")
    func otherReply_hugsLeading() {
        let (cell, bubble) = laidOutCell(sender: .other, quote: shortQuote)
        #expect(abs(bubble.minX - 12) < 0.5)
        #expect(bubble.maxX < cell.contentView.bounds.width - 12)
    }

    @Test("A quote wider than the body does not push the bubble past maxWidth")
    func longQuote_respectsMaxWidth() {
        let (_, bubble) = laidOutCell(sender: .me, quote: longQuote, text: "ok")
        #expect(bubble.width <= Self.maxWidth + 0.5)
    }

    @Test("Adding a quote does not move the bubble sideways")
    func quote_doesNotShiftTheBubble() {
        let plain = laidOutCell(sender: .me, quote: nil)
        let quoted = laidOutCell(sender: .me, quote: shortQuote)
        // The height changes; the trailing edge must not.
        #expect(abs(plain.bubbleFrame.maxX - quoted.bubbleFrame.maxX) < 0.5)
    }

    @Test("A quote wider than the body widens the bubble to hold it")
    func longQuote_widensTheBubble() {
        let narrow = laidOutCell(sender: .me, quote: nil, text: "ok")
        let (_, wide) = laidOutCell(sender: .me, quote: longQuote, text: "ok")
        #expect(wide.width > narrow.bubbleFrame.width)
    }
}
