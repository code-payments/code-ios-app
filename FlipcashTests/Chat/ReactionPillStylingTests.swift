//
//  ReactionPillStylingTests.swift
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
@Suite("Reaction pill styling")
struct ReactionPillStylingTests {

    private static let gold = UIColor(Color.reactionBoost)

    private static func pill(count: UInt64 = 2, cents: UInt64?, selfReacted: Bool) -> ReactionPill {
        ReactionPill(emoji: "👍", count: count, selfReacted: selfReacted, pending: false, boost: cents.map { ReactionBoost(total: $0) })
    }

    private static func labels(in view: UIView) -> [UILabel] {
        view.subviews.flatMap { sub -> [UILabel] in
            if let label = sub as? UILabel { return [label] }
            return labels(in: sub)
        }
    }

    private static func amountLabel(in view: ReactionPillView) -> UILabel? {
        labels(in: view).first { $0.text?.hasPrefix("$") == true }
    }

    private static func countLabel(in view: ReactionPillView) -> UILabel? {
        labels(in: view).first { $0.text == "2" }
    }

    private static func same(_ a: UIColor?, _ b: UIColor) -> Bool {
        a?.cgColor == b.cgColor
    }

    @Test("A boosted pill the viewer reacted to is gold")
    func paidSelfReacted_isGold() throws {
        let view = ReactionPillView()
        view.configure(with: Self.pill(cents: 100, selfReacted: true), canReact: true)
        #expect(Self.same(view.backgroundColor, Self.gold.withAlphaComponent(0.1)))
        #expect(view.layer.borderWidth == 2)
        #expect(view.layer.borderColor == Self.gold.cgColor)
        #expect(Self.same(try #require(Self.amountLabel(in: view)).textColor, Self.gold))
        #expect(Self.same(try #require(Self.countLabel(in: view)).textColor, Self.gold.withAlphaComponent(0.5)))
    }

    @Test("Someone else's boosted pill keeps the resting look")
    func paidByOthers_isNotGold() throws {
        let view = ReactionPillView()
        view.configure(with: Self.pill(cents: 100, selfReacted: false), canReact: true)
        #expect(Self.same(view.backgroundColor, UIColor.white.withAlphaComponent(0.06)))
        #expect(view.layer.borderWidth == 0)
        #expect(Self.same(try #require(Self.amountLabel(in: view)).textColor, UIColor.white.withAlphaComponent(0.5)))
        #expect(Self.same(try #require(Self.countLabel(in: view)).textColor, UIColor(Color.textMain)))
    }

    @Test("An unpaid pill the viewer reacted to keeps its white outline")
    func unpaidSelfReacted_isWhite() {
        let view = ReactionPillView()
        view.configure(with: Self.pill(cents: nil, selfReacted: true), canReact: true)
        #expect(Self.same(view.backgroundColor, UIColor.white.withAlphaComponent(0.12)))
        #expect(view.layer.borderWidth == 2)
        #expect(view.layer.borderColor == UIColor.white.withAlphaComponent(0.24).cgColor)
    }

    @Test("Reacting to someone else's boosted pill turns it gold")
    func paidPill_selfReactedFlip_turnsGold() throws {
        let view = ReactionPillView()
        view.configure(with: Self.pill(cents: 100, selfReacted: false), canReact: true)
        view.configure(with: Self.pill(cents: 100, selfReacted: true), canReact: true, animated: true)
        #expect(view.layer.borderWidth == 2)
        #expect(view.layer.borderColor == Self.gold.cgColor)
        #expect(Self.same(try #require(Self.amountLabel(in: view)).textColor, Self.gold))
    }

    /// Cells are reconfigured inside the transcript's animated updates, where a `UIStackView` counts
    /// each `isHidden = true` on an already-hidden arranged subview and one `false` no longer shows it.
    @Test("A boost that arrives after reconfigures inside animations still shows its amount")
    func boostAfterAnimatedReconfigures_showsAmount() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        let view = ReactionPillView()
        window.addSubview(view)
        window.isHidden = false
        view.configure(with: Self.pill(cents: nil, selfReacted: false), canReact: true)
        for _ in 0..<3 {
            UIView.animate(withDuration: 0.3) {
                view.configure(with: Self.pill(cents: nil, selfReacted: true), canReact: true, animated: true)
                view.layoutIfNeeded()
            }
        }
        view.configure(with: Self.pill(cents: 100, selfReacted: true), canReact: true, animated: true)
        view.frame = CGRect(origin: .zero, size: view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize))
        view.layoutIfNeeded()
        let label = try #require(Self.amountLabel(in: view))
        #expect(!label.isHidden)
        #expect(label.bounds.width >= label.intrinsicContentSize.width - 0.5)
    }
}
