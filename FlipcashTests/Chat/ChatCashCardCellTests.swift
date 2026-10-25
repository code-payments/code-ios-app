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

    private let plain = ChatMessage(id: "1", content: .cash(ChatCashContent(amount: "$5.00", token: "Cash")), sender: .me)

    private let group = ChatMessage(id: "2", content: .cash(ChatCashContent(
        amount: "$1.23", token: "Jeffy",
        group: .init(caption: "Alex sent", each: "~$0.61 each", recipients: "to You and 1 Other")
    )), sender: .other)

    /// What `ChatColumnCell.preferredLayoutAttributesFitting` asks the cell for.
    private func measure(_ message: ChatMessage, in cell: ChatCashCardCell = ChatCashCardCell(frame: .zero)) -> CGFloat {
        cell.configure(with: message, maxWidth: 250)
        return cell.contentView.systemLayoutSizeFitting(
            CGSize(width: Self.width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
    }

    @Test("A group card grows past the fixed cash card to fit its lines")
    func groupCard_isTallerThanCashCard() {
        #expect(measure(group) > measure(plain))
    }

    @Test("A cell recycled from a group card to a cash card measures at the cash card's height")
    func reusedCell_groupToCash_restoresFixedHeight() {
        let cell = ChatCashCardCell(frame: .zero)
        _ = measure(group, in: cell)
        #expect(measure(plain, in: cell) == measure(plain))
    }
}
