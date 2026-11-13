//
//  ChatInviteCardCellTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI

/// The group-ready card's cell switching between its two styles. Its hosting content view traps
/// when a configuration's root view type differs from the one it was made with, so each style has
/// to go through the same root type, including when a reused cell changes style.
@MainActor
@Suite("Chat invite card cell")
struct ChatInviteCardCellTests {

    private func height(of cell: ChatInviteCardCell) -> CGFloat {
        cell.contentView.systemLayoutSizeFitting(
            CGSize(width: 390, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
    }

    @Test("A new cell configures as the empty state")
    func newCellConfiguresAsEmptyState() {
        let cell = ChatInviteCardCell(frame: CGRect(x: 0, y: 0, width: 390, height: 200))

        cell.configure(groupName: "Ski Trip", style: .emptyState, maxWidth: 390)

        #expect(height(of: cell) > 0)
    }

    @Test("A reused cell switches between the bubble and the empty state")
    func reusedCellSwitchesStyle() {
        let cell = ChatInviteCardCell(frame: CGRect(x: 0, y: 0, width: 390, height: 200))

        cell.configure(groupName: "Ski Trip", style: .incomingBubble, maxWidth: 390)
        let bubble = height(of: cell)
        cell.prepareForReuse()
        cell.configure(groupName: "Ski Trip", style: .emptyState, maxWidth: 390)
        let emptyState = height(of: cell)
        cell.prepareForReuse()
        cell.configure(groupName: "Ski Trip", style: .incomingBubble, maxWidth: 390)

        #expect(bubble > 0)
        #expect(emptyState > 0)
        #expect(height(of: cell) == bubble)
    }

    @Test("The empty state draws no bubble, and a reused cell draws it again for the bubble style")
    func emptyStateDrawsNoBubble() {
        let cell = ChatInviteCardCell(frame: CGRect(x: 0, y: 0, width: 390, height: 200))
        let chrome = cell.descendants(of: BubbleBackgroundView.self).first

        cell.configure(groupName: "Ski Trip", style: .emptyState, maxWidth: 390)
        let emptyStateDraws = chrome?.isDrawingBubble
        cell.prepareForReuse()
        cell.configure(groupName: "Ski Trip", style: .incomingBubble, maxWidth: 390)

        #expect(emptyStateDraws == false)
        #expect(chrome?.isDrawingBubble == true)
    }
}
