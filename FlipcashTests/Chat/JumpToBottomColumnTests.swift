//
//  JumpToBottomColumnTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import Testing
import UIKit
import FlipcashCore
@testable import Flipcash
@testable import FlipcashUI

/// The jump-to-bottom column's place over the bar's trailing control.
@MainActor
@Suite("Jump to bottom column")
struct JumpToBottomColumnTests {

    @Test("The trailing control's centre inset is the control inset plus half its height")
    func trailingControlCentreInset_values() {
        // The composing column is asserted on the function: the spring that carries the view there
        // does not advance in a test host with no display.
        #expect(BarMetrics.trailingControlCentreInset(isCompact: true) == BarMetrics.compactInset + BarMetrics.contentHeight / 2)
        #expect(BarMetrics.trailingControlCentreInset(isCompact: false) == BarMetrics.edgeInset + BarMetrics.contentHeight / 2)
    }

    @Test("The button stands twice the field-to-$ gap above $, whichever way the bar rests")
    func jumpButtonGap_isTwiceTheFieldGap() {
        #expect(ConversationBottomBar.leadingSpacing == BarMetrics.controlSpacing)
        #expect(BarMetrics.jumpButtonGap == BarMetrics.controlSpacing * 2)
        // Measured from the bar's top edge, which stands the bar's margin above `$`.
        #expect(BarMetrics.jumpButtonGapAboveBar + BarMetrics.contentPadding == BarMetrics.jumpButtonGap)
        #expect(JumpToBottomButtonView.reach.height >= JumpToBottomButtonView.diameter + BarMetrics.jumpButtonGapAboveBar)
    }

    @Test("The button takes touches on its circle and badge only, and only while shown")
    func hitsButton_circleAndBadgeOnly() {
        let model = JumpToBottomModel()
        model.buttonFrame = CGRect(x: 300, y: 600, width: 44, height: 44)
        let centre = CGPoint(x: 322, y: 622)
        #expect(!model.hitsButton(at: centre), "Hidden")

        model.isVisible = true
        #expect(model.hitsButton(at: centre))
        #expect(!model.hitsButton(at: CGPoint(x: 300 - 20, y: 622)), "20pt left of the circle")
        #expect(!model.hitsButton(at: CGPoint(x: 301, y: 601)), "The square's corner")

        let overhang = CGPoint(x: 346, y: 598)
        #expect(!model.hitsButton(at: overhang), "No badge, no overhang")
        model.unreadCount = 3
        #expect(model.hitsButton(at: overhang))

        model.isSuppressed = true
        #expect(!model.hitsButton(at: centre))
    }
}
