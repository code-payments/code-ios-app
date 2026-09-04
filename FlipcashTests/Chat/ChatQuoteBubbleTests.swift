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
