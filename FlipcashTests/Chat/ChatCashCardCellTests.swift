//
//  ChatCashCardCellTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI

@MainActor
@Suite("ChatCashCardCell height")
struct ChatCashCardCellTests {

    private static let width: CGFloat = 393

    private let dm = ChatMessage(id: "1", content: .cash(ChatCashContent(
        amount: "$5.00", token: "Cash",
        lines: .init(caption: "You sent", counterpart: "to Noah Parker")
    )), sender: .me)

    private let group = ChatMessage(id: "2", content: .cash(ChatCashContent(
        amount: "$1.00", token: "Jeffy",
        lines: .init(caption: "You and 2 others received", total: "$3.00 total", part: .each, counterpart: "from Fred Wilson")
    )), sender: .other)

    /// What `ChatColumnCell.preferredLayoutAttributesFitting` asks the cell for.
    private func measure(_ message: ChatMessage, in cell: ChatCashCardCell = ChatCashCardCell(frame: .zero), maxWidth: CGFloat = 250) -> CGFloat {
        cell.configure(with: message, maxWidth: maxWidth)
        return cell.contentView.systemLayoutSizeFitting(
            CGSize(width: Self.width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
    }

    private func labels(in view: UIView) -> [UILabel] {
        view.subviews.flatMap { ($0 as? UILabel).map { [$0] } ?? labels(in: $0) }
    }

    @Test("A group card grows past a DM card by its total line")
    func groupCard_isTallerThanDMCard() {
        #expect(measure(group) > measure(dm))
    }

    private func offered(_ state: ChatCashContent.SendBack?) -> ChatMessage {
        ChatMessage(id: "3", content: .cash(ChatCashContent(
            amount: "$5.00", token: "Cash",
            lines: .init(caption: "Noah Parker sent", counterpart: "to you"),
            sendBack: state
        )), sender: .other)
    }

    @Test("A Send Back row adds to the card's height in every state")
    func sendBackRow_growsCard() {
        let plain = measure(offered(nil))
        for state in [ChatCashContent.SendBack.available, .sending, .sentBack] {
            #expect(measure(offered(state)) > plain)
        }
    }

    @Test("The Send Back row is 44 tall under the card's padding; the Sent Back footer is 36 in place of it")
    func sendBackRow_sizes() {
        let plain = measure(offered(nil))
        #expect((measure(offered(.available)) - plain).rounded() == 44)
        #expect((measure(offered(.sending)) - plain).rounded() == 44)
        // 36 for the footer, less the 16 bottom padding it replaces.
        #expect((measure(offered(.sentBack)) - plain).rounded() == 20)
    }

    @Test("A cell recycled from an offered card to a plain one drops the row")
    func reusedCell_sendBackToPlain_measuresFresh() {
        let cell = ChatCashCardCell(frame: .zero)
        _ = measure(offered(.sending), in: cell)
        #expect(measure(offered(nil), in: cell) == measure(offered(nil)))
    }

    @Test("A cell recycled from a group card to a DM card measures as a fresh one")
    func reusedCell_groupToDM_measuresFresh() {
        let cell = ChatCashCardCell(frame: .zero)
        _ = measure(group, in: cell)
        #expect(measure(dm, in: cell) == measure(dm))
    }

    @Test("A long amount with its 'each' shrinks to fit the card on one line")
    func longEach_fitsCard() throws {
        let long = ChatMessage(id: "3", content: .cash(ChatCashContent(
            amount: "$12,345,678.90", token: "Jeffy",
            lines: .init(caption: "You sent", total: "$98,765,432.10 total", part: .each, counterpart: "to Alex Morgan and 9 others")
        )), sender: .me)
        let cell = ChatCashCardCell(frame: CGRect(x: 0, y: 0, width: Self.width, height: 400))
        let height = measure(long, in: cell, maxWidth: 232)
        cell.frame.size.height = height
        cell.layoutIfNeeded()
        let amount = try #require(labels(in: cell.contentView).first { $0.attributedText?.string.hasSuffix(" each") == true })
        let card = try #require(amount.superview?.superview)
        let frame = amount.convert(amount.bounds, to: card)
        #expect(frame.minX >= 0 && frame.maxX <= card.bounds.width)
        #expect(amount.numberOfLines == 1)
    }

    @Test("The smallest of uneven parts leads with a '~' at 70% of the amount's size and keeps a half-size Medium 'each'")
    func approximateEach_styles() throws {
        let uneven = ChatMessage(id: "4", content: .cash(ChatCashContent(
            amount: "$0.33", token: "Jeffy",
            lines: .init(caption: "You and 2 others received", total: "$1.00 total", part: .approximateEach, counterpart: "from Fred Wilson")
        )), sender: .other)
        let cell = ChatCashCardCell(frame: .zero)
        cell.configure(with: uneven, maxWidth: 250)
        let text = try #require(labels(in: cell.contentView).compactMap(\.attributedText).first { $0.string.hasSuffix(" each") })
        #expect(text.string == "~$0.33 each")
        let tilde = try #require(text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        let amount = try #require(text.attribute(.font, at: 1, effectiveRange: nil) as? UIFont)
        let each = try #require(text.attribute(.font, at: text.length - 1, effectiveRange: nil) as? UIFont)
        #expect(abs(tilde.pointSize / amount.pointSize - 0.7) < 0.02)
        #expect(tilde.fontName == amount.fontName)
        #expect(text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor == text.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? UIColor)
        #expect(text.attribute(.baselineOffset, at: 0, effectiveRange: nil) == nil)
        #expect(each.pointSize == amount.pointSize / 2)
        #expect(each.fontName == UIFont.default(size: each.pointSize, weight: .medium).fontName)
    }

    @Test("A long uneven amount shrinks its '~' with the rest of the line to fit the card")
    func longApproximate_fitsCard() throws {
        let long = ChatMessage(id: "6", content: .cash(ChatCashContent(
            amount: "$1,234,567.89", token: "Jeffy",
            lines: .init(caption: "You sent", total: "$9,876,543.21 total", part: .approximateEach, counterpart: "to Alex Morgan and 7 others")
        )), sender: .me)
        let cell = ChatCashCardCell(frame: CGRect(x: 0, y: 0, width: Self.width, height: 400))
        cell.frame.size.height = measure(long, in: cell, maxWidth: 232)
        cell.layoutIfNeeded()
        let amount = try #require(labels(in: cell.contentView).first { $0.attributedText?.string.hasPrefix("~") == true })
        let card = try #require(amount.superview?.superview)
        let frame = amount.convert(amount.bounds, to: card)
        #expect(frame.minX >= 0 && frame.maxX <= card.bounds.width)
        #expect(amount.numberOfLines == 1 && amount.adjustsFontSizeToFitWidth)
    }

    private func laidOut(_ message: ChatMessage) -> (cell: ChatCashCardCell, labels: [UILabel]) {
        let cell = ChatCashCardCell(frame: CGRect(x: 0, y: 0, width: Self.width, height: 400))
        cell.frame.size.height = measure(message, in: cell)
        cell.layoutIfNeeded()
        return (cell, labels(in: cell.contentView))
    }

    /// The card's lines top to bottom, each as a frame in the card's coordinates, with the card's
    /// own bounds: the edges the spec's spacing values run between.
    private func lineFrames(_ message: ChatMessage, texts: [String]) throws -> (card: CGRect, lines: [CGRect]) {
        let (cell, all) = laidOut(message)
        let views: [UIView] = try texts.map { text in
            let label = try #require(all.first { ($0.text ?? $0.attributedText?.string) == text })
            // The token's name sits in a row with its icon; the row is the line.
            return label.superview is UIStackView && label.superview?.superview is UIStackView ? label.superview! : label
        }
        let card = try #require(views.first?.superview?.superview)
        return (card.bounds, views.map { $0.convert($0.bounds, to: card) })
    }

    /// The gaps from the card's top, between each pair of lines, and to the card's bottom.
    private func gaps(_ layout: (card: CGRect, lines: [CGRect])) -> [CGFloat] {
        let edges = [layout.card.minY] + layout.lines.flatMap { [$0.minY, $0.maxY] } + [layout.card.maxY]
        return stride(from: 0, to: edges.count, by: 2).map { (edges[$0 + 1] - edges[$0]).rounded() }
    }

    @Test("A group card spaces its lines 16 / 12 / 0 / 6 / 12 / 16, so its height is its lines plus those gaps")
    func groupCard_spacing() throws {
        let layout = try lineFrames(group, texts: ["You and 2 others received", "$1.00 each", "$3.00 total", "Jeffy", "from Fred Wilson"])
        #expect(gaps(layout) == [16, 12, 0, 6, 12, 16])
    }

    @Test("A card with no total spaces its lines 16 / 12 / 6 / 12 / 16")
    func dmCard_spacing() throws {
        let layout = try lineFrames(dm, texts: ["You sent", "$5.00", "Cash", "to Noah Parker"])
        #expect(gaps(layout) == [16, 12, 6, 12, 16])
    }
}
