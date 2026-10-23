//
//  ReactionPillBoostLayoutTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI

@MainActor
@Suite("Reaction pill boost layout")
struct ReactionPillBoostLayoutTests {

    private static func pill(_ emoji: String, count: UInt64, cents: UInt64?, selfReacted: Bool = false) -> ReactionPill {
        ReactionPill(emoji: emoji, count: count, selfReacted: selfReacted, pending: false, boost: cents.map(ReactionBoost.init))
    }

    private static func layOut(_ row: ReactionPillRowView) {
        row.frame = CGRect(origin: .zero, size: row.sizeThatFits(CGSize(width: 280, height: CGFloat.greatestFiniteMagnitude)))
        row.layoutIfNeeded()
    }

    /// Amount labels inside the row's pills, skipping the "$" boost button.
    private static func amountLabels(in row: ReactionPillRowView) -> [UILabel] {
        row.subviews.filter { $0 is ReactionPillView }.flatMap(labels(in:))
    }

    private static func labels(in view: UIView) -> [UILabel] {
        view.subviews.flatMap { sub -> [UILabel] in
            if let label = sub as? UILabel, label.text?.hasPrefix("$") == true, !label.isHidden { return [label] }
            return labels(in: sub)
        }
    }

    @Test("A boosted pill gives its amount room", arguments: [(UInt64(1), false), (1, true), (2, false), (2, true)])
    func boostedPill_showsAmount(count: UInt64, selfReacted: Bool) throws {
        let row = ReactionPillRowView()
        row.layoutWidth = 280
        row.configure(pills: [Self.pill("👍", count: count, cents: 100, selfReacted: selfReacted)], canReact: true, canBoost: true)
        Self.layOut(row)
        let label = try #require(Self.amountLabels(in: row).first)
        #expect(label.bounds.width >= label.intrinsicContentSize.width - 0.5)
    }

    @Test("A boosted pill keeps its amount after a live count change")
    func boostedPill_countChange_keepsAmount() throws {
        let row = ReactionPillRowView()
        row.layoutWidth = 280
        row.configure(pills: [Self.pill("👍", count: 1, cents: 100)], canReact: true, canBoost: true)
        Self.layOut(row)
        row.configure(pills: [Self.pill("👍", count: 2, cents: 100)], canReact: true, canBoost: true)
        Self.layOut(row)
        let label = try #require(Self.amountLabels(in: row).first)
        #expect(label.bounds.width >= label.intrinsicContentSize.width - 0.5)
    }

    /// Whether the row's first pill shows its whole amount label within its bounds.
    private static func amountInsidePill(in row: ReactionPillRowView) -> Bool {
        guard let label = amountLabels(in: row).first,
              let pill = row.subviews.first(where: { $0 is ReactionPillView }) else { return false }
        let frame = label.convert(label.bounds, to: pill)
        return label.bounds.width >= label.intrinsicContentSize.width - 0.5
            && frame.minX >= 0
            && frame.maxX <= pill.bounds.width + 0.5
    }

    /// A boost new to a pill has no room reserved, so it shows on the row's next beat.
    @Test("A pill that turns boosted shows its amount inside the pill after the beat", arguments: [(UInt64(1), true), (2, false)])
    func turnsBoosted_afterBeat_amountInsidePill(count: UInt64, selfReacted: Bool) async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        let row = ReactionPillRowView()
        row.layoutWidth = 280
        window.addSubview(row)
        window.isHidden = false
        row.configure(pills: [Self.pill("👍", count: count, cents: nil, selfReacted: selfReacted)], canReact: true, canBoost: true)
        Self.layOut(row)
        row.configure(pills: [Self.pill("👍", count: count, cents: 100, selfReacted: selfReacted)], canReact: true, canBoost: true)
        Self.layOut(row)
        try await waitUntil {
            Self.layOut(row)
            return Self.amountInsidePill(in: row)
        }
    }
}
