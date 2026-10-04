//
//  AttachOverlayModeTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
@testable import Flipcash

@MainActor
@Suite("Attach overlay mode")
struct AttachOverlayModeTests {

    /// A locator that finds `window`, or nothing, and counts how often it was asked.
    private final class StubLocator: KeyboardWindowLocating {
        let window: UIWindow?
        private(set) var lookups = 0

        init(window: UIWindow?) {
            self.window = window
        }

        func keyboardWindow() -> UIWindow? {
            lookups += 1
            return window
        }
    }

    private static let keyboardHeight: CGFloat = 336

    @Test("A found keyboard window draws the panel over the live keys")
    func keyboardWindowWins() {
        let window = UIWindow(frame: .zero)
        let plan = AttachOverlayPlan(
            locator: StubLocator(window: window),
            keyboardHeight: Self.keyboardHeight,
            canReplaceInputView: true
        )
        #expect(plan.mode == .keyboardWindow)
        #expect(plan.keyboardWindow === window)
    }

    @Test("No keyboard window falls back to swapping the field's input view")
    func missingWindowFallsBackToInputView() {
        let plan = AttachOverlayPlan(
            locator: StubLocator(window: nil),
            keyboardHeight: Self.keyboardHeight,
            canReplaceInputView: true
        )
        #expect(plan.mode == .inputView)
        #expect(plan.keyboardWindow == nil)
    }

    @Test("No keyboard window and no swappable field takes the keyboard down, as before")
    func nothingLeftDismissesTheKeyboard() {
        let plan = AttachOverlayPlan(
            locator: StubLocator(window: nil),
            keyboardHeight: Self.keyboardHeight,
            canReplaceInputView: false
        )
        #expect(plan.mode == .dismissKeyboard)
        #expect(!plan.mode.drawsOverKeyboard)
    }

    @Test("With the keyboard down the private lookup is never made", arguments: [CGFloat(0), 44])
    func keyboardDownSkipsTheLookup(height: CGFloat) {
        let locator = StubLocator(window: UIWindow(frame: .zero))
        let plan = AttachOverlayPlan(locator: locator, keyboardHeight: height, canReplaceInputView: true)
        #expect(plan.mode == .dismissKeyboard)
        #expect(plan.keyboardWindow == nil)
        #expect(locator.lookups == 0)
    }

    @Test("Only the software keyboard's height counts as a keyboard to draw over")
    func selectionThresholds() {
        let minimum = AttachOverlayMode.minimumKeyboardHeight
        #expect(AttachOverlayMode.select(keyboardHeight: minimum - 1, hasKeyboardWindow: true, canReplaceInputView: true) == .dismissKeyboard)
        #expect(AttachOverlayMode.select(keyboardHeight: minimum, hasKeyboardWindow: true, canReplaceInputView: false) == .keyboardWindow)
        #expect(AttachOverlayMode.select(keyboardHeight: minimum, hasKeyboardWindow: false, canReplaceInputView: true) == .inputView)
    }

    @Test("The panel straddles the composer's bottom edge, clears its top, and grows out of +")
    func panelStraddlesTheComposerEdge() {
        let plus = CGRect(x: 12, y: 500, width: 50, height: 50)
        let size = CGSize(width: 240, height: 144)
        let frame = AttachOverlayLayout.panelFrame(plusFrame: plus, size: size)
        #expect(frame.minX == plus.minX - BarMetrics.fieldPadding)
        #expect(frame.minY < frame.maxY && frame.minY <= plus.maxY && frame.maxY >= plus.maxY)
        let fieldTop = plus.maxY + BarMetrics.fieldPadding - BarMetrics.contentHeight
        #expect(frame.minY <= fieldTop - AttachOverlayLayout.fieldTopOverhang)

        let anchor = AttachOverlayLayout.panelAnchor(plusFrame: plus, size: size)
        #expect(frame.minX + anchor.x * size.width == plus.midX)
        #expect(frame.minY + anchor.y * size.height == plus.midY)
    }

    @Test("The card stands on the screen's bottom, inset from its sides")
    func cardStandsOnTheScreenBottom() {
        let bounds = CGRect(x: 0, y: 0, width: 402, height: 874)
        let frame = AttachOverlayLayout.cardFrame(in: bounds, height: 507)
        #expect(frame.maxY == bounds.maxY - AttachOverlayLayout.cardInset)
        #expect(frame.minX == AttachOverlayLayout.cardInset)
        #expect(frame.width == bounds.width - AttachOverlayLayout.cardInset * 2)
        #expect(frame.height == 507)
    }

    @Test("The live host returns a window or nil, and never traps")
    func liveHostIsSafe() {
        // No keyboard is up in the test host, so there is nothing to find; the call itself must hold.
        _ = KeyboardOverlayHost().keyboardWindow()
    }

    @Test("A card drawn over the keyboard stays up as the keyboard announces itself")
    func cardIgnoresKeyboardShowOverKeyboard() {
        let card = AttachCard()
        card.open(.photos, screenHeight: 800)
        card.closesOnKeyboardShow = false
        card.keyboardWillShow()
        #expect(card.isOpen)

        card.closesOnKeyboardShow = true
        card.keyboardWillShow()
        #expect(!card.isOpen)
    }

    @Test("A card over the keyboard asks the bar for no room, since it takes its own touches")
    func overflowStaysOffForCardOverKeyboard() {
        let model = ConversationBarModel()
        model.attachCard.open(.photos, screenHeight: 800)
        #expect(model.overflow != .none)

        model.overKeyboard.activate(items: [.camera, .photos])
        #expect(model.overflow == .none)
    }

    @Test("The landing chip's frame is kept only while a landing is under way")
    func landingTracksOnlyItsChip() {
        let card = AttachCard()
        let frame = CGRect(x: 20, y: 600, width: 64, height: 64)

        card.landingChipDidLayout(frame)
        #expect(card.landingChipFrame == nil)

        card.beginLanding(on: UUID())
        card.landingChipDidLayout(.zero)
        #expect(card.landingChipFrame == nil, "An unlaid-out chip has no frame to land on")
        card.landingChipDidLayout(frame)
        #expect(card.landingChipFrame == frame)

        card.endLanding()
        #expect(card.landingChipID == nil && card.landingChipFrame == nil)
    }

    // MARK: - Touches outside the panel

    @Test("A touch outside the panel is taken while the menu dismisses on it")
    func outsideTouch_takenWhenDismissing() {
        let container = AttachOverlayContainer(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        container.hitRects[.panel] = CGRect(x: 10, y: 500, width: 200, height: 200)
        var dismisses = true
        container.dismissesOnOutsideTouch = { dismisses }

        #expect(container.hitTest(CGPoint(x: 300, y: 750), with: nil) === container)

        dismisses = false
        #expect(container.hitTest(CGPoint(x: 300, y: 750), with: nil) == nil)
    }

    @Test("A touch outside the panel fires the dismiss")
    func outsideTouch_firesDismiss() {
        let container = AttachOverlayContainer(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        var fired = 0
        container.onOutsideTouch = { fired += 1 }

        container.touchesBegan([], with: nil)

        #expect(fired == 1)
    }
}
