//
//  ChatLinkCardSplitTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashCore
import FlipcashUI
@testable import Flipcash

@MainActor
@Suite("A message with a link card splits into rows")
struct ChatLinkCardSplitTests {

    private let me = UUID()
    private let them = UUID()
    private let base = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_000_000))
        .addingTimeInterval(9 * 60 * 60)

    private static let cashLink = "https://send.flipcash.com/c/#/e=KNi8pQr1n5hRU65vKJGge3"

    private func text(
        _ id: UInt64,
        _ sender: UUID,
        _ body: String,
        after offset: TimeInterval = 0,
        edited: Bool = false,
        repliedTo: UInt64? = nil
    ) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id),
            senderID: sender,
            content: .text(body),
            date: base.addingTimeInterval(offset),
            unreadSeq: id,
            lastEditedTs: edited ? base.addingTimeInterval(offset + 1) : nil,
            repliedTo: repliedTo.map { MessageID(value: $0) }
        )
    }

    /// Cards the cash link and nothing else, the way the classifier would.
    private func cashCard(_ links: [DetectedLink]) -> LinkCard? {
        links.first { $0.url.absoluteString == Self.cashLink }.map {
            .cash(LinkCard.Cash(url: $0.url, entropy: "KNi8pQr1n5hRU65vKJGge3", range: $0.range))
        }
    }

    /// The cash card when there is one, else the first link as a web card, as the classifier picks.
    private func cashOrWebCard(_ links: [DetectedLink]) -> LinkCard? {
        cashCard(links) ?? links.first.map { .web(LinkCard.Web(url: $0.url, range: $0.range)) }
    }

    private func rows(
        _ messages: [ConversationMessage],
        linkCard: @escaping ([DetectedLink]) -> LinkCard? = { _ in nil }
    ) -> [ChatMessage] {
        ChatItem.from(
            messages,
            selfUserID: me,
            quotedMessage: { id in messages.first { $0.id == id } },
            linkCard: { [self] links in linkCard(links) ?? cashCard(links) }
        )
        .compactMap { if case .message(let message) = $0 { message } else { nil } }
    }

    private func body(_ row: ChatMessage) -> String? {
        if case .text(let text) = row.content { text } else { nil }
    }

    // MARK: - Order and content

    @Test("Text before and after the link become their own bubbles around the card, in order")
    func splitsInSourceOrder() {
        let rows = rows([text(1, me, "here you go \(Self.cashLink) enjoy")])

        #expect(rows.map(\.part?.kind) == [.leadingText, .card, .trailingText])
        #expect(rows.map(body) == ["here you go", Self.cashLink, "enjoy"])
        #expect(rows.map(\.rendersAsBareLinkCard) == [false, true, false])
    }

    @Test("A link that ends the message leaves no empty row after the card")
    func dropsEmptyTrailingSegment() {
        let rows = rows([text(1, me, "here you go:\n\(Self.cashLink)  ")])
        #expect(rows.map(\.part?.kind) == [.leadingText, .card])
        #expect(rows.map(body) == ["here you go:", Self.cashLink])
    }

    @Test("A link-only message is one bare card row")
    func linkOnlyIsOneCardRow() {
        let rows = rows([text(1, me, Self.cashLink)])
        #expect(rows.map(\.part?.kind) == [.card])
        #expect(rows[0].rendersAsBareLinkCard)
    }

    @Test("A web link stays in one text bubble that keeps the link and the card")
    func webLinkIsOneTextRow() throws {
        let body = "read this https://example.com/post today"
        let rows = rows([text(1, me, body)], linkCard: cashOrWebCard)
        #expect(rows.count == 1)
        #expect(rows[0].part == nil)
        #expect(self.body(rows[0]) == body)
        #expect(!rows[0].rendersAsBareLinkCard)
        let card = try #require(rows[0].linkPreview?.card)
        guard case .web = card else { Issue.record("expected a web card, got \(card)"); return }
    }

    @Test("A link-only web message is a text bubble too, not a bare card")
    func webLinkOnlyIsNotBare() {
        let rows = rows([text(1, me, "https://example.com/post")], linkCard: cashOrWebCard)
        #expect(rows.count == 1)
        #expect(rows[0].part == nil)
        #expect(!rows[0].rendersAsBareLinkCard)
    }

    @Test("A whitespace-only segment is dropped, not drawn as an empty bubble")
    func dropsWhitespaceOnlySegments() {
        let rows = rows([text(1, me, " \n \(Self.cashLink) \n ")])
        #expect(rows.map(\.part?.kind) == [.card])
    }

    @Test("Punctuation touching the link goes with it, rather than drawing a bubble of its own")
    func dropsPunctuationTouchingTheLink() {
        #expect(rows([text(1, me, "hi \(Self.cashLink).")]).map(body) == ["hi", Self.cashLink])
        #expect(rows([text(1, me, "(\(Self.cashLink))")]).map(body) == [Self.cashLink])
        #expect(rows([text(1, me, "\(Self.cashLink), then lunch")]).map(body) == [Self.cashLink, "then lunch"])
        #expect(rows([text(1, me, "\"\(Self.cashLink)\" enjoy")]).map(body) == [Self.cashLink, "enjoy"])
    }

    @Test("Punctuation set apart from the link by a space stays with its words")
    func keepsPunctuationAcrossAGap() {
        #expect(rows([text(1, me, "is this you? \(Self.cashLink)")]).map(body) == ["is this you?", Self.cashLink])
        #expect(rows([text(1, me, "look: \(Self.cashLink)")]).map(body) == ["look:", Self.cashLink])
    }

    @Test("A segment of nothing but punctuation is dropped")
    func dropsPunctuationOnlySegments() {
        #expect(rows([text(1, me, "\(Self.cashLink) !!")]).map(\.part?.kind) == [.card])
        #expect(rows([text(1, me, "... \(Self.cashLink)")]).map(\.part?.kind) == [.card])
    }

    @Test("An emoji or symbol beside the link is content, and keeps its row")
    func keepsEmojiAndSymbols() {
        #expect(rows([text(1, me, "\(Self.cashLink) 🎉")]).map(body) == [Self.cashLink, "🎉"])
        #expect(rows([text(1, me, "\(Self.cashLink) $5")]).map(body) == [Self.cashLink, "$5"])
    }

    @Test("The card row's span is its whole text, so the card lines up with its row")
    func cardRowSpanIsRebased() throws {
        let rows = rows([text(1, me, "look \(Self.cashLink)")])
        let card = try #require(rows.last?.linkPreview?.card)
        #expect(card.range == NSRange(location: 0, length: (Self.cashLink as NSString).length))
    }

    @Test("Other links stay underlined in their text row, with spans moved into that row")
    func otherLinksStayInline() throws {
        let rows = rows([text(1, me, "\(Self.cashLink) and https://apple.com")])
        #expect(rows.map(\.part?.kind) == [.card, .trailingText])

        let trailing = try #require(rows.last)
        #expect(body(trailing) == "and https://apple.com")
        #expect(trailing.linkPreview?.card == nil)
        let link = try #require(trailing.linkPreview?.links.first)
        #expect(link.range == NSRange(location: 4, length: 17))
        #expect(link.url == URL(string: "https://apple.com"))
    }

    @Test("A text row with no link of its own takes the plain text cell")
    func plainSegmentHasNoPreview() {
        let rows = rows([text(1, me, "hi \(Self.cashLink)")])
        #expect(rows.first?.linkPreview == nil)
    }

    @Test("A message with no card stays one row")
    func noCardIsOneRow() {
        let rows = rows([text(1, me, "see https://apple.com")])
        #expect(rows.count == 1)
        #expect(rows[0].part == nil)
        #expect(rows[0].id == rows[0].messageID)
    }

    // MARK: - Mentions

    @Test("A message with only a mention takes the link cell, with the mention's span")
    func mentionOnly_carriesPreview() throws {
        let rows = rows([text(1, me, "ask @jeff")])
        let preview = try #require(rows.first?.linkPreview)
        #expect(preview.links.isEmpty)
        #expect(preview.mentions.map(\.username.value) == ["jeff"])
        #expect(preview.mentions.first?.range == NSRange(location: 4, length: 5))
    }

    @Test("A mention past the card moves into its own row's frame")
    func mentionRebasedIntoTrailingRow() throws {
        let rows = rows([text(1, me, "here \(Self.cashLink) from @jeff")])
        #expect(rows.map(\.part?.kind) == [.leadingText, .card, .trailingText])

        #expect(rows[0].linkPreview == nil)
        #expect(rows[1].linkPreview?.mentions.isEmpty == true)
        let trailing = try #require(rows[2].linkPreview)
        #expect(body(rows[2]) == "from @jeff")
        #expect(trailing.mentions.first?.range == NSRange(location: 5, length: 5))
    }

    // MARK: - Ids

    @Test("Every row has a unique id, and all of them name the same message")
    func idsAreUniqueAndShareTheMessage() {
        let rows = rows([text(1, me, "a \(Self.cashLink) b"), text(2, me, "c", after: 60)])
        #expect(Set(rows.map(\.id)).count == rows.count)
        #expect(Set(rows.prefix(3).map(\.messageID)).count == 1)
        #expect(rows[3].messageID != rows[0].messageID)
    }

    @Test("A split row copies the whole message")
    func splitRowCarriesTheWholeText() {
        let whole = "a \(Self.cashLink) b"
        let rows = rows([text(1, me, whole)])
        #expect(rows.allSatisfy { $0.part?.messageText == whole })
    }

    // MARK: - Decorations

    @Test("The quote heads the first row; the receipt and Edited close the last")
    func decorationsGoToTheEnds() {
        let rows = rows([
            text(1, them, "dinner?"),
            text(2, me, "yes \(Self.cashLink) enjoy", after: 60, edited: true, repliedTo: 1),
        ])
        let split = Array(rows.dropFirst())

        #expect(split.map { $0.quote != nil } == [true, false, false])
        #expect(split.map(\.isEdited) == [false, false, true])
        #expect(split.map { $0.receipt != nil } == [false, false, true])
    }

    @Test("A reply that opens with the card still draws the card bare, under its quote")
    func replyCardIsBare() {
        let rows = rows([
            text(1, them, "dinner?"),
            text(2, me, Self.cashLink, after: 60, edited: true, repliedTo: 1),
        ])
        let card = rows[1]
        #expect(card.rendersAsBareLinkCard)
        #expect(card.quote != nil)
        #expect(card.isEdited)
    }

    @Test("Every row of a split message offers the whole message's menu")
    func everyRowCarriesTheActions() {
        let messages = [text(1, me, "a \(Self.cashLink) b")]
        let rows = ChatItem.from(
            messages,
            selfUserID: me,
            capabilities: { _ in [.reply, .copy] },
            linkCard: cashCard
        )
        .compactMap { if case .message(let message) = $0 { message } else { nil } }
        #expect(rows.count == 3)
        #expect(rows.allSatisfy { !$0.actions.isEmpty && $0.actions == rows[0].actions })
    }

    // MARK: - Bubble run

    @Test("A card joins the bubble run on both sides, inside and outside its message")
    func cardJoinsTheBubbleRun() {
        let rows = rows([
            text(1, me, "before", after: 0),
            text(2, me, "a \(Self.cashLink) b", after: 60),
            text(3, me, "after", after: 120),
        ])
        #expect(rows.map(\.part?.kind) == [nil, .leadingText, .card, .trailingText, nil])

        // The author run is one run of five.
        #expect(rows.map(\.isContinuationFromPrevious) == [false, true, true, true, true])
        #expect(rows.map(\.isContinuedByNext) == [true, true, true, true, false])

        // The card is cut to a bubble's shape, so the bubble run is the author run.
        #expect(rows.map(\.joinsBubbleAbove) == [false, true, true, true, true])
        #expect(rows.map(\.joinsBubbleBelow) == [true, true, true, true, false])
    }

    @Test("A link-only message joins the bubbles on either side of it")
    func linkOnlyMessageJoinsItsNeighbours() {
        let rows = rows([
            text(1, me, "before", after: 0),
            text(2, me, Self.cashLink, after: 60),
            text(3, me, "after", after: 120),
        ])
        #expect(rows.map(\.joinsBubbleAbove) == [false, true, true])
        #expect(rows.map(\.joinsBubbleBelow) == [true, true, false])
    }
}
