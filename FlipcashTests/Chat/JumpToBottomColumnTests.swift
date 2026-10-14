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

/// The jump-to-bottom column, driven by the model the screen fills in and by the bar's focus.
@MainActor
@Suite("Jump to bottom column")
struct JumpToBottomColumnTests {

    @MainActor
    private final class Harness {
        let jump = JumpToBottomModel()
        let bar = ConversationBarModel()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let host: UIHostingController<JumpToBottomColumn>
        var taps = 0

        init() {
            host = UIHostingController(rootView: JumpToBottomColumn(jump: jump, bar: bar))
            host.view.backgroundColor = .clear
            host.safeAreaRegions = []
            jump.onTap = { [unowned self] in taps += 1 }
            window.rootViewController = host
            window.makeKeyAndVisible()
            let size = JumpToBottomColumn.size
            host.view.frame = CGRect(x: 390 - size.width, y: 700, width: size.width, height: size.height)
            host.view.layoutIfNeeded()
        }

        var button: JumpToBottomButton? { find(in: host.view) }

        private func find(in view: UIView) -> JumpToBottomButton? {
            if let button = view as? JumpToBottomButton { return button }
            return view.subviews.lazy.compactMap { self.find(in: $0) }.first
        }

        /// The button's centre in the host's coordinates.
        var buttonCentre: CGPoint {
            guard let button else { return .zero }
            return button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: host.view)
        }

        /// Whether the button, or something inside it, is what a touch at `point` reaches.
        func buttonTakesTouch(at point: CGPoint) -> Bool {
            var view = host.view.hitTest(point, with: nil)
            while let current = view {
                if current is JumpToBottomButton { return true }
                view = current.superview
            }
            return false
        }

        /// Lets the springs finish.
        func settle() async throws {
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(2000))
            host.view.layoutIfNeeded()
        }
    }

    @Test("Visibility set on the model shows the button and lets it take taps")
    func visibility_drivesTheButton() async throws {
        let harness = Harness()
        try await harness.settle()
        let button = try #require(harness.button)

        // Hidden: nothing takes the tap, though the button is still laid out there.
        #expect(!harness.buttonTakesTouch(at: harness.buttonCentre))

        harness.jump.isVisible = true
        try await harness.settle()
        #expect(harness.buttonTakesTouch(at: harness.buttonCentre))

        button.sendActions(for: .touchUpInside)
        #expect(harness.taps == 1)

        harness.jump.isVisible = false
        try await harness.settle()
        #expect(!harness.buttonTakesTouch(at: harness.buttonCentre))
    }

    @Test("The count set on the model is the badge")
    func count_drivesTheBadge() async throws {
        let harness = Harness()
        harness.jump.isVisible = true
        harness.jump.unreadCount = 3
        try await harness.settle()
        let button = try #require(harness.button)

        #expect(button.accessibilityLabel == "Jump to latest message")
        #expect(button.accessibilityValue == UnreadBadgeText.text(for: 3))

        harness.jump.unreadCount = 0
        try await harness.settle()
        #expect(button.accessibilityValue == nil)
    }

    @Test("A touch beside the button, inside the column, falls through")
    func touchBesideTheButton_fallsThrough() async throws {
        let harness = Harness()
        harness.jump.isVisible = true
        try await harness.settle()

        let beside = CGPoint(x: harness.buttonCentre.x - JumpToButtonGeometry.radius - 8, y: harness.buttonCentre.y)
        #expect(harness.host.view.bounds.contains(beside))
        #expect(!harness.buttonTakesTouch(at: beside))
    }

    @Test("The button rests over the bar's trailing control while compact")
    func column_restsOverTheTrailingControl() async throws {
        let harness = Harness()
        harness.jump.isVisible = true
        try await harness.settle()
        let width = harness.host.view.bounds.width

        let compact = BarMetrics.trailingControlCentreInset(isCompact: true)
        #expect(abs((width - harness.buttonCentre.x) - compact) < 0.5)
    }

    @Test("The trailing control's centre inset is the control inset plus half its height")
    func trailingControlCentreInset_values() {
        // The composing column is asserted on the function: the spring that carries the view there
        // does not advance in a test host with no display.
        #expect(BarMetrics.trailingControlCentreInset(isCompact: true) == BarMetrics.compactInset + BarMetrics.contentHeight / 2)
        #expect(BarMetrics.trailingControlCentreInset(isCompact: false) == BarMetrics.edgeInset + BarMetrics.contentHeight / 2)
    }
}

private enum JumpToButtonGeometry {
    @MainActor static let radius = JumpToBottomButtonView.diameter / 2
}
