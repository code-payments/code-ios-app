//
//  ReactionRowLongPressTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI

@MainActor
@Suite("Reaction row long press")
struct ReactionRowLongPressTests {

    private static func row(_ emoji: [String], trailing: Bool = false) -> ReactionPillRowView {
        let row = ReactionPillRowView()
        row.layoutWidth = 280
        row.hugsTrailingEdge = trailing
        row.configure(
            pills: emoji.map { ReactionPill(emoji: $0, count: 1, selfReacted: false, pending: false) },
            canReact: true
        )
        row.frame = CGRect(origin: .zero, size: row.sizeThatFits(CGSize(width: 280, height: CGFloat.greatestFiniteMagnitude)))
        row.layoutIfNeeded()
        return row
    }

    @Test("A press in the gap above a pill opens that pill's reactors")
    func gapAbovePill_resolvesToPill() {
        let row = Self.row(["👍"])
        #expect(row.longPressEmoji(at: CGPoint(x: 20, y: 1)) == "👍")
    }

    @Test("A press in the slack beside the viewer's own pills resolves to the nearest one")
    func slack_resolvesToNearestPill() {
        let row = Self.row(["👍", "🔥"], trailing: true)
        #expect(row.longPressEmoji(at: CGPoint(x: 4, y: 18)) == "👍")
    }

    @Test("The row owns the long press, and leaves the \"+\" its own touch")
    func addButton_isExcluded() throws {
        let row = Self.row(["👍"])
        #expect(row.gestureRecognizers?.contains { $0 is UILongPressGestureRecognizer } == true)
        let add = try #require(row.subviews.first { $0 is UIControl && !$0.isHidden })
        #expect(row.longPressEmoji(at: CGPoint(x: add.frame.midX, y: add.frame.midY)) == nil)
    }
}
