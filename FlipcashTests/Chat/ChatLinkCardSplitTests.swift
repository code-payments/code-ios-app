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

    private func rows(_ messages: [ConversationMessage]) -> [ChatMessage] {
        ChatItem.from(
            messages,
            selfUserID: me,
            quotedMessage: { id in messages.first { $0.id == id } },
            linkCard: cashCard
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

    @Test("A whitespace-only segment is dropped, not drawn as an empty bubble")
    func dropsWhitespaceOnlySegments() {
        let rows = rows([text(1, me, " \n \(Self.cashLink) \n ")])
        #expect(rows.map(\.part?.kind) == [.card])
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

    @Test("A card breaks the bubble run on both sides, inside and outside its message")
    func cardBreaksTheBubbleRun() {
        let rows = rows([
            text(1, me, "before", after: 0),
            text(2, me, "a \(Self.cashLink) b", after: 60),
            text(3, me, "after", after: 120),
        ])
        #expect(rows.map(\.part?.kind) == [nil, .leadingText, .card, .trailingText, nil])

        // The author run is one run of five.
        #expect(rows.map(\.isContinuationFromPrevious) == [false, true, true, true, true])
        #expect(rows.map(\.isContinuedByNext) == [true, true, true, true, false])

        // "before" joins "a"; everything facing the card stands alone; "b" joins "after".
        #expect(rows.map(\.joinsBubbleAbove) == [false, true, false, false, true])
        #expect(rows.map(\.joinsBubbleBelow) == [true, false, false, true, false])
    }

    @Test("A neighbour of a link-only message does not join toward it")
    func linkOnlyNeighboursStandAlone() {
        let rows = rows([
            text(1, me, "before", after: 0),
            text(2, me, Self.cashLink, after: 60),
            text(3, me, "after", after: 120),
        ])
        #expect(rows.map(\.joinsBubbleAbove) == [false, false, false])
        #expect(rows.map(\.joinsBubbleBelow) == [false, false, false])
    }
}
