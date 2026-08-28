//
//  ChatReceiptViewTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI

@MainActor
@Suite("ChatReceiptView state machine")
struct ChatReceiptViewTests {

    private func makeView() -> ChatReceiptView {
        ChatReceiptView(frame: CGRect(x: 0, y: 0, width: 200, height: 20))
    }

    @Test("A nil receipt renders nothing and takes no height")
    func nilReceiptIsEmpty() {
        let view = makeView()
        view.setReceipt(nil, animated: false)
        #expect(view.isHidden)
        #expect(view.currentStatusText == nil)
    }

    @Test("Delivered renders a status and no timestamp")
    func deliveredRendersStatusOnly() {
        let view = makeView()
        view.setReceipt(.delivered, animated: false)
        #expect(!view.isHidden)
        #expect(view.currentStatusText == "Delivered")
        #expect(view.currentTimeText == nil)
    }

    @Test("A dated read renders both runs")
    func readRendersStatusAndTime() {
        let view = makeView()
        view.setReceipt(.read(time: "3:42 PM"), animated: false)
        #expect(view.currentStatusText == "Read")
        #expect(view.currentTimeText == "3:42 PM")
    }

    @Test("Delivered to Read swaps in place, leaving the outgoing text on the back face")
    func deliveredToReadSwapsInPlace() {
        let view = makeView()
        view.setReceipt(.delivered, animated: false)
        view.setReceipt(.read(time: "3:42 PM"), animated: true)
        // The front face carries the arriving state; the outgoing one is handed to the back face so
        // both are on screen for the length of the cross-fade.
        #expect(view.currentStatusText == "Read")
        #expect(view.outgoingStatusText == "Delivered")
    }

    @Test("The outgoing face keeps the colour of the state it is carrying away")
    func outgoingFaceKeepsItsOwnColor() {
        let view = makeView()
        view.setReceipt(.failed("Not Delivered. Tap to retry"), animated: false)
        view.setReceipt(.delivered, animated: true)
        // Reading the front's colour after it has already been restyled would fade the red line out
        // as white — the outgoing face has to be coloured from the state it is showing.
        #expect(view.outgoingColor == ChatReceiptView.failedColor)
        #expect(view.currentColor == ChatReceiptView.defaultColor)
    }

    @Test("A failed receipt turns the line red; a resolved one turns it back")
    func failedReceiptIsRed() {
        let view = makeView()
        view.setReceipt(.failed("Not Delivered. Tap to retry"), animated: false)
        #expect(view.currentStatusText == "Not Delivered. Tap to retry")
        #expect(view.currentColor == ChatReceiptView.failedColor)
        view.setReceipt(.delivered, animated: false)
        #expect(view.currentColor == ChatReceiptView.defaultColor)
    }

    @Test("Re-applying the same receipt is a no-op, so a remap can't restart the swap")
    func reapplyingSameReceiptDoesNotSwap() {
        let view = makeView()
        view.setReceipt(.delivered, animated: false)
        view.setReceipt(.read(time: "3:42 PM"), animated: true)
        view.setReceipt(.read(time: "3:42 PM"), animated: true)
        // The back face still holds the *original* outgoing state — the second call did nothing.
        #expect(view.outgoingStatusText == "Delivered")
    }

    @Test("A Read line whose timestamp resolves later updates without a swap")
    func readTimeArrivingLaterIsNotASwap() {
        let view = makeView()
        view.setReceipt(.read(time: nil), animated: false)
        view.setReceipt(.read(time: "3:42 PM"), animated: true)
        // Same status, so there is nothing to cross-fade against — the line just gains its time.
        #expect(view.currentTimeText == "3:42 PM")
        #expect(view.outgoingStatusText == nil)
    }

    @Test("Clearing the receipt collapses the line without animating it away")
    func clearingCollapses() {
        let view = makeView()
        view.setReceipt(.delivered, animated: false)
        view.setReceipt(nil, animated: true)
        #expect(view.isHidden)
        #expect(view.currentStatusText == nil)
    }

    @Test("The line snaps to where the column puts it instead of sliding in from the stack's origin")
    func geometryDoesNotAnimate() {
        let view = makeView()
        // The reveal runs inside the transcript's batch-update animation block, which would otherwise
        // spring the newly-unhidden line down from the stack's origin, across the bubble.
        #expect(view.action(for: view.layer, forKey: "position") is NSNull)
        #expect(view.action(for: view.layer, forKey: "bounds") is NSNull)
    }

    @Test("Reset drops a swap in flight so a recycled cell starts clean")
    func resetDropsASwapInFlight() {
        let view = makeView()
        view.setReceipt(.delivered, animated: false)
        view.setReceipt(.read(time: "3:42 PM"), animated: true)
        view.reset()
        #expect(view.isHidden)
        #expect(view.currentReceipt == nil)
        #expect(view.currentStatusText == nil)
        #expect(view.outgoingStatusText == nil)
    }
}
