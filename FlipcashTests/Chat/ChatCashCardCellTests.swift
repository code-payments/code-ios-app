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

    @Test("The smallest of uneven parts leads with a '~' at 70% of the amount's size and keeps a lighter 'each'")
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
        #expect(each.pointSize < amount.pointSize && each.fontName != amount.fontName)
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

    /// The empty space between the bottom of one label's glyphs and the top of the next's: frame
    /// gap plus the space under the baseline and over the cap height. Digits and these captions
    /// have no descenders, so this is what reads as the gap.
    private func visibleGap(_ upper: UILabel, _ lower: UIView, in root: UIView) -> CGFloat {
        let upperFrame = upper.convert(upper.bounds, to: root)
        let lowerFrame = lower.convert(lower.bounds, to: root)
        let upperFont = upper.attributedText?.attribute(.font, at: 0, effectiveRange: nil) as? UIFont ?? upper.font!
        let below = -upperFont.descender + (upper.bounds.height - upperFont.lineHeight) / 2
        var above: CGFloat = 0
        if let lower = lower as? UILabel {
            above = lower.font.ascender - lower.font.capHeight + (lower.bounds.height - lower.font.lineHeight) / 2
        }
        return lowerFrame.minY + above - (upperFrame.maxY - below)
    }

    private func laidOut(_ message: ChatMessage) -> (cell: ChatCashCardCell, labels: [UILabel]) {
        let cell = ChatCashCardCell(frame: CGRect(x: 0, y: 0, width: Self.width, height: 400))
        cell.frame.size.height = measure(message, in: cell)
        cell.layoutIfNeeded()
        return (cell, labels(in: cell.contentView))
    }

    @Test("The total sits closer under the amount than any other pair of lines, and the token row farther")
    func moneyReadsAsOneBlock() throws {
        let (cell, all) = laidOut(group)
        let root = cell.contentView
        let caption = try #require(all.first { $0.text == "You and 2 others received" })
        let amount = try #require(all.first { $0.attributedText?.string == "$1.00 each" })
        let total = try #require(all.first { $0.text == "$3.00 total" })
        let token = try #require(all.first { $0.text == "Jeffy" })
        let footer = try #require(all.first { $0.text == "from Fred Wilson" })
        let tokenRow = try #require(token.superview)

        let amountToTotal = visibleGap(amount, total, in: root)
        let totalToToken = visibleGap(total, tokenRow, in: root)
        #expect(amountToTotal < totalToToken)
        #expect(amountToTotal < visibleGap(caption, amount, in: root))
        #expect(amountToTotal < footer.convert(footer.bounds, to: root).minY - tokenRow.convert(tokenRow.bounds, to: root).maxY)
    }

    @Test("With no total, the token row sits as far under the amount as it does under a total")
    func noTotal_tokenGapMatchesGroup() throws {
        let (groupCell, groupLabels) = laidOut(group)
        let (dmCell, dmLabels) = laidOut(dm)
        let total = try #require(groupLabels.first { $0.text == "$3.00 total" })
        let groupToken = try #require(groupLabels.first { $0.text == "Jeffy" }?.superview)
        let dmAmount = try #require(dmLabels.first { $0.attributedText?.string == "$5.00" })
        let dmToken = try #require(dmLabels.first { $0.text == "Cash" }?.superview)
        let groupGap = visibleGap(total, groupToken, in: groupCell.contentView)
        let dmGap = visibleGap(dmAmount, dmToken, in: dmCell.contentView)
        #expect(abs(groupGap - dmGap) <= 1.5, "group \(groupGap) vs no-total \(dmGap)")
    }
}
