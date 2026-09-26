//
//  LinkableBubbleViewTests.swift
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
@Suite("LinkableBubbleView")
struct LinkableBubbleViewTests {

    private func url(_ s: String) -> URL { URL(string: s)! }

    @Test("Configuring renders the message text")
    func configure_setsText() {
        let view = LinkableBubbleView()
        view.configure(with: ChatMessage(id: "1", text: "see https://apple.com", sender: .me))
        #expect(view.descendants(of: UITextView.self).first?.text == "see https://apple.com")
    }

    @Test("The text view refuses to become first responder, so selection stays off")
    func textView_refusesFirstResponder() {
        let view = LinkableBubbleView()
        #expect(view.descendants(of: UITextView.self).first?.canBecomeFirstResponder == false)
    }

    @Test("The text view's own data detection is off, so LinkDetector is the only detector")
    func textView_leavesDetectionToLinkDetector() {
        let view = LinkableBubbleView()
        #expect(view.descendants(of: UITextView.self).first?.dataDetectorTypes == [])
    }

    @Test("Every detected span gets a link attribute, not just the trailing one")
    func linkedText_marksEverySpan() throws {
        let text = "see https://apple.com and https://example.com"
        let message = ChatMessage(
            id: "1",
            text: text,
            sender: .me,
            linkPreview: LinkPreview(links: [
                DetectedLink(range: NSRange(location: 4, length: 17), url: url("https://apple.com")),
                DetectedLink(range: NSRange(location: 26, length: 19), url: url("https://example.com")),
            ])
        )

        let rendered = try #require(LinkableBubbleView.linkedText(for: message))
        var linked: [URL] = []
        rendered.enumerateAttribute(.link, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in
            if let url = value as? URL { linked.append(url) }
        }
        #expect(linked == [url("https://apple.com"), url("https://example.com")])
    }

    @Test("A span past the end of the text is dropped rather than trapping")
    func linkedText_clampsStaleSpans() throws {
        let message = ChatMessage(
            id: "1",
            text: "hi",
            sender: .me,
            linkPreview: LinkPreview(links: [
                DetectedLink(range: NSRange(location: 0, length: 40), url: url("https://apple.com")),
            ])
        )

        let rendered = try #require(LinkableBubbleView.linkedText(for: message))
        var linked = 0
        rendered.enumerateAttribute(.link, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in
            if value != nil { linked += 1 }
        }
        #expect(linked == 0)
    }

    // MARK: - A card row

    private static let cashLink = "https://send.flipcash.com/c/#/e=KNi8pQr1n5hRU65vKJGge3"

    /// The row the transcript gives a carded link: its text is the link and nothing else.
    private func cardRow(quote: ChatQuote? = nil, isEdited: Bool = false) -> ChatMessage {
        let link = DetectedLink(
            range: NSRange(location: 0, length: (Self.cashLink as NSString).length),
            url: url(Self.cashLink)
        )
        return ChatMessage(
            id: "1#card",
            text: Self.cashLink,
            sender: .me,
            linkPreview: LinkPreview(
                links: [link],
                card: .cash(LinkCard.Cash(url: link.url, entropy: "KNi8pQr1n5hRU65vKJGge3", range: link.range))
            ),
            isEdited: isEdited,
            quote: quote,
            part: ChatMessagePart(messageID: "1", kind: .card, messageText: Self.cashLink)
        )
    }

    private static let groupLink = "https://app.flipcash.com/g/abc"

    /// A group-invite card row, the other card shape the transcript draws bare.
    private func groupCardRow(sender: ChatMessage.Sender, above: Bool, below: Bool) -> ChatMessage {
        let range = NSRange(location: 0, length: (Self.groupLink as NSString).length)
        return ChatMessage(
            id: "1#card",
            text: Self.groupLink,
            sender: sender,
            joinsBubbleAbove: above,
            joinsBubbleBelow: below,
            linkPreview: LinkPreview(
                links: [DetectedLink(range: range, url: url(Self.groupLink))],
                card: .group(LinkCard.Group(url: url(Self.groupLink), chatID: ConversationID(data: Data(repeating: 7, count: 32)), range: range))
            ),
            part: ChatMessagePart(messageID: "1", kind: .card, messageText: Self.groupLink)
        )
    }

    private func cashCardRow(sender: ChatMessage.Sender, above: Bool, below: Bool) -> ChatMessage {
        let range = NSRange(location: 0, length: (Self.cashLink as NSString).length)
        return ChatMessage(
            id: "1#card",
            text: Self.cashLink,
            sender: sender,
            joinsBubbleAbove: above,
            joinsBubbleBelow: below,
            linkPreview: LinkPreview(
                links: [DetectedLink(range: range, url: url(Self.cashLink))],
                card: .cash(LinkCard.Cash(url: url(Self.cashLink), entropy: "KNi8pQr1n5hRU65vKJGge3", range: range))
            ),
            part: ChatMessagePart(messageID: "1", kind: .card, messageText: Self.cashLink)
        )
    }

    /// Alone, top, middle and bottom of a run, from each side.
    private static let runPositions: [(sender: ChatMessage.Sender, above: Bool, below: Bool)] = [
        (.me, false, false), (.me, false, true), (.me, true, true), (.me, true, false),
        (.other, false, false), (.other, false, true), (.other, true, true), (.other, true, false),
    ]

    @Test("A card's corners match a text bubble's at every run position, for every card kind")
    func cardRadii_matchTheTextBubble() {
        for position in Self.runPositions {
            let textView = LinkableBubbleView()
            textView.configure(with: ChatMessage(
                id: "2",
                text: "hi",
                sender: position.sender,
                joinsBubbleAbove: position.above,
                joinsBubbleBelow: position.below
            ))
            let textRadii = chrome(textView)?.radii

            for row in [
                cashCardRow(sender: position.sender, above: position.above, below: position.below),
                groupCardRow(sender: position.sender, above: position.above, below: position.below),
            ] {
                let cardView = LinkableBubbleView()
                cardView.configure(with: row)
                #expect(cardView.cardCornerRadii == textRadii, "\(position) \(row.linkPreview?.card as Any)")
            }
        }
    }

    @Test("A card in the middle of a run flattens both inner corners toward its neighbours")
    func cardRadii_middleOfRunIsFlattened() {
        let view = LinkableBubbleView()
        view.configure(with: cashCardRow(sender: .me, above: true, below: true))
        #expect(view.cardCornerRadii.topTrailing == BubbleBackgroundView.groupedRadius)
        #expect(view.cardCornerRadii.bottomTrailing == BubbleBackgroundView.groupedRadius)
        #expect(view.cardCornerRadii.topLeading == BubbleBackgroundView.baseRadius)
    }

    @Test("A recycled card row takes the new position's corners")
    func cardRadii_followReuse() {
        let view = LinkableBubbleView()
        view.configure(with: cashCardRow(sender: .me, above: true, below: true))
        view.configure(with: groupCardRow(sender: .other, above: false, below: false))
        #expect(view.cardCornerRadii == BubbleBackgroundView.standaloneRadii)
    }

    private func chrome(_ view: LinkableBubbleView) -> BubbleBackgroundView? {
        view.descendants(of: BubbleBackgroundView.self).first
    }

    @Test("Tapping the card hands back the card")
    func cardTap_reportsTheCard() {
        let view = LinkableBubbleView()
        var tapped: [URL] = []
        view.onLinkCardTap = { tapped.append($0.url) }
        view.configure(with: cardRow())
        view.cardTapped()
        #expect(tapped == [url(Self.cashLink)])
    }

    @Test("A bubble recycled from a card row to a plain one reports nothing")
    func cardTap_afterReuse() {
        let view = LinkableBubbleView()
        var tapped: [URL] = []
        view.onLinkCardTap = { tapped.append($0.url) }
        view.configure(with: cardRow())
        view.configure(with: ChatMessage(id: "2", text: "see https://apple.com", sender: .me))
        view.cardTapped()
        #expect(tapped.isEmpty)
    }

    /// The card is already a surface with its own rounded shape, so a bubble behind it draws a
    /// second, slightly larger card around the first. Android's `BareLinkCard` gate.
    @Test("A card row draws the card with no bubble behind it")
    func cardRow_dropsTheBubble() {
        let view = LinkableBubbleView()
        view.configure(with: cardRow())
        #expect(chrome(view)?.isDrawingBubble == false)
        #expect(view.descendants(of: UITextView.self).first?.isHidden == true)
    }

    @Test("A reply whose first row is the card still draws the card bare, under its quote")
    func replyCardRow_isBare() {
        let view = LinkableBubbleView()
        view.configure(with: cardRow(quote: ChatQuote(stableID: "7", authorName: "Ada", snippet: "dinner at 7?", kind: .text)))
        #expect(chrome(view)?.isDrawingBubble == false)
        #expect(view.quotePanel.isHidden == false)
    }

    @Test("An edited card row is bare, with no marker inside the row")
    func editedCardRow_isBare() {
        let view = LinkableBubbleView()
        view.configure(with: cardRow(isEdited: true))
        #expect(chrome(view)?.isDrawingBubble == false)
    }

    @Test("A bubble recycled from a card row back to ordinary text draws its bubble and text again")
    func reuse_cardToText_restoresTheBubble() {
        let view = LinkableBubbleView()
        view.configure(with: cardRow())
        view.configure(with: ChatMessage(id: "2", text: "see https://apple.com", sender: .me,
                                         linkPreview: LinkPreview(url: url("https://apple.com"))))
        #expect(chrome(view)?.isDrawingBubble == true)
        #expect(view.descendants(of: UITextView.self).first?.isHidden == false)
    }
}
