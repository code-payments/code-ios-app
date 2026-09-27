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

    @Test("A mention is tagged with its handle and padded for its pill, without becoming a link")
    func linkedText_tagsMentions() throws {
        let message = ChatMessage(
            id: "1",
            text: "ask @jeff",
            sender: .me,
            linkPreview: LinkPreview(links: [], mentions: [
                DetectedMention(range: NSRange(location: 4, length: 5), username: Username("jeff")!),
            ])
        )

        let rendered = try #require(LinkableBubbleView.linkedText(for: message))
        let mention = NSRange(location: 4, length: 5)
        var effective = NSRange()
        let tag = rendered.attribute(.textItemTag, at: 4, longestEffectiveRange: &effective, in: NSRange(location: 0, length: rendered.length)) as? String
        #expect(tag == "jeff")
        #expect(effective == mention)
        #expect(rendered.attribute(.underlineStyle, at: 4, effectiveRange: nil) == nil)
        #expect(rendered.attribute(.kern, at: 3, effectiveRange: nil) as? CGFloat == MentionPill.spacing)
        #expect(rendered.attribute(.kern, at: 8, effectiveRange: nil) as? CGFloat == MentionPill.spacing)
        #expect(rendered.attribute(.kern, at: 4, effectiveRange: nil) == nil)
        #expect(rendered.attribute(.link, at: 4, effectiveRange: nil) == nil)
        #expect(rendered.attribute(.textItemTag, at: 0, effectiveRange: nil) == nil)
    }

    @Test("A mention's pill reaches past the handle by the same padding on both sides")
    func mentionPill_rect() {
        let line = CGRect(x: 40, y: 10, width: 50, height: 20)
        #expect(MentionPill.rect(around: line) == CGRect(x: 40 - MentionPill.padding, y: 10, width: 50 + 2 * MentionPill.padding, height: 20))
    }

    @Test("A tap resolves to the link or mention under it, and to nothing off every span")
    func span_findsTheTappedItem() throws {
        let message = ChatMessage(
            id: "1",
            text: "ask @jeff at https://apple.com",
            sender: .me,
            linkPreview: LinkPreview(
                links: [DetectedLink(range: NSRange(location: 13, length: 17), url: url("https://apple.com"))],
                mentions: [DetectedMention(range: NSRange(location: 4, length: 5), username: Username("jeff")!)]
            )
        )

        let rendered = try #require(LinkableBubbleView.linkedText(for: message))
        #expect(LinkableBubbleView.span(in: rendered, at: 4) == .mention(Username("jeff")!))
        #expect(LinkableBubbleView.span(in: rendered, at: 8) == .mention(Username("jeff")!))
        #expect(LinkableBubbleView.span(in: rendered, at: 20) == .url(url("https://apple.com")))
        #expect(LinkableBubbleView.span(in: rendered, at: 0) == nil)
        #expect(LinkableBubbleView.span(in: rendered, at: 10) == nil)
        #expect(LinkableBubbleView.span(in: rendered, at: rendered.length) == nil)
    }

    @Test("The text view carries its own span tap, so a tap that lowers the keyboard still opens the span")
    func textView_carriesSpanTap() {
        let view = LinkableBubbleView()
        let textView = view.descendants(of: UITextView.self).first
        #expect(textView?.gestureRecognizers?.contains { $0.delegate === view } == true)
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

    private static let personLink = "https://flipcash.com/satoshi"

    /// A person card row, the one card that hugs its content rather than filling the column.
    private func personCardRow(sender: ChatMessage.Sender, above: Bool, below: Bool) -> ChatMessage {
        let range = NSRange(location: 0, length: (Self.personLink as NSString).length)
        return ChatMessage(
            id: "1#card",
            text: Self.personLink,
            sender: sender,
            joinsBubbleAbove: above,
            joinsBubbleBelow: below,
            linkPreview: LinkPreview(
                links: [DetectedLink(range: range, url: url(Self.personLink))],
                card: .user(LinkCard.User(url: url(Self.personLink), identity: .username(Username("satoshi")!), range: range))
            ),
            part: ChatMessagePart(messageID: "1", kind: .card, messageText: Self.personLink)
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
                personCardRow(sender: position.sender, above: position.above, below: position.below),
            ] {
                let cardView = LinkableBubbleView()
                cardView.configure(with: row)
                #expect(cardView.cardCornerRadii == textRadii, "\(position) \(row.linkPreview?.card as Any)")
            }
        }
    }

    @Test("The person card itself is cut to the run's corners, not only its slot")
    func personCardRadii_reachTheCard() {
        let view = LinkableBubbleView()
        view.configure(with: personCardRow(sender: .other, above: true, below: true))
        let card = view.descendants(of: LinkUserCardView.self).first
        #expect(card?.cornerRadii == BubbleBackgroundView.radii(isFromSelf: false, groupedAbove: true, groupedBelow: true))
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

    @Test(
        "A mention's pill is its handle's width plus the same padding on both sides",
        arguments: ["@erik", "Talk to @erik about that", "hey @erik, did it", "(@erik)", "ask @erik", "@jeff @erik"]
    )
    func mentionPill_evenPadding(text: String) throws {
        // The kern either side of a handle leaks into its selection rect, differently mid-line and at
        // the end of a line, so a pill sized from that rect comes out lopsided.
        let links = LinkDetector().webLinks(in: text)
        let mentions = MentionDetector.mentions(in: text, excluding: links)
        let view = LinkableBubbleView()
        view.configure(with: ChatMessage(id: "1", text: text, sender: .me,
                                         linkPreview: LinkPreview(links: links, mentions: mentions)))
        view.frame = CGRect(x: 0, y: 0, width: 330, height: 200)
        view.layoutIfNeeded()

        let textView = try #require(view.descendants(of: LinkTextView.self).first)
        let mention = try #require(mentions.last)
        let pill = try #require(textView.mentionPillRects.last)
        let handle = NSMutableAttributedString(attributedString: textView.attributedText.attributedSubstring(from: mention.range))
        handle.removeAttribute(.kern, range: NSRange(location: 0, length: handle.length))

        #expect(abs(pill.width - (handle.size().width + 2 * MentionPill.padding)) < 0.5)
    }
}
