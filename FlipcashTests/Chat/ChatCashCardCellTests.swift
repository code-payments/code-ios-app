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
        lines: .init(caption: "You and 2 others received", total: "$3.00 total", counterpart: "from Fred Wilson")
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
            lines: .init(caption: "You sent", total: "$98,765,432.10 total", counterpart: "to Alex Morgan and 9 others")
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
}
