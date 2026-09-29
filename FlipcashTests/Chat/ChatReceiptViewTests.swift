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

    @Test("Clearing the receipt collapses the line, and with no host there is nothing to fade")
    func clearingCollapses() {
        let view = makeView()
        view.setReceipt(.delivered, animated: false)
        view.setReceipt(nil, animated: true)
        #expect(view.isHidden)
        #expect(view.currentStatusText == nil)
    }

    /// A receipt laid out inside a host, the way a cell's content view holds it.
    private func makeHostedView() -> (view: ChatReceiptView, host: UIView) {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 80))
        let view = makeView()
        host.addSubview(view)
        view.exitHost = host
        view.setReceipt(.delivered, animated: false)
        view.layoutIfNeeded()
        return (view, host)
    }

    @Test("An animated clear leaves a copy of the line fading in the host while the view empties")
    func animatedClearLeavesAFadingCopy() throws {
        let (view, host) = makeHostedView()
        view.setReceipt(nil, animated: true)
        // The view itself collapses at once, so the row can close inside the batch update.
        #expect(view.isHidden)
        #expect(view.currentStatusText == nil)
        let copy = try #require(view.fadingLine)
        #expect(copy.superview === host)
        #expect(view.fadingStatusText == "Delivered")
    }

    @Test("A clear that isn't animated leaves nothing behind")
    func unanimatedClearLeavesNoCopy() {
        let (view, host) = makeHostedView()
        view.setReceipt(nil, animated: false)
        #expect(view.fadingLine == nil)
        #expect(host.subviews == [view])
    }

    @Test("Reset takes a fading copy away, so a recycled cell can't carry it")
    func resetRemovesTheFadingCopy() {
        let (view, host) = makeHostedView()
        view.setReceipt(nil, animated: true)
        view.reset()
        #expect(view.fadingLine == nil)
        #expect(host.subviews == [view])
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

    // Physics compare within a tolerance: Core Animation keeps a spring's constants at single precision.

    /// The spring animation on `face` for `keyPath`, as the receipt added it.
    private func springAnimation(on face: UIView, _ keyPath: String) -> CASpringAnimation? {
        (face.layer.animationKeys() ?? [])
            .compactMap { face.layer.animation(forKey: $0) as? CASpringAnimation }
            .first { $0.keyPath == keyPath }
    }

    @Test("A reveal inside the batch update's animation rides the Delivered spring from its start state")
    func revealKeepsItsOwnSpringInsideABatch() throws {
        let view = makeView()
        ChatMotion.reflow.animate {
            view.setReceipt(.delivered, animated: true)
        }
        let opacity = try #require(springAnimation(on: view.currentFace, "opacity"))
        #expect(abs(opacity.stiffness - ChatMotion.delivered.stiffness) < 0.001)
        #expect(abs(opacity.damping - ChatMotion.delivered.damping) < 0.001)
        #expect((opacity.fromValue as? Float) == 0)
        let transform = try #require(springAnimation(on: view.currentFace, "transform"))
        #expect(abs(transform.stiffness - ChatMotion.delivered.stiffness) < 0.001)
        let start = try #require((transform.fromValue as? NSValue)?.caTransform3DValue)
        #expect(abs(start.m11 - ChatMotion.deliveredScale) < 0.0001)
        // The face rests where the spring ends, so nothing is left for the batch's spring to carry.
        #expect(view.currentFace.alpha == 1)
        #expect(view.currentFace.transform == .identity)
    }

    @Test("A swap inside the batch update's animation rides the Read spring on both faces")
    func swapKeepsItsOwnSpringInsideABatch() throws {
        let view = makeView()
        view.setReceipt(.delivered, animated: false)
        ChatMotion.reflow.animate {
            view.setReceipt(.read(time: "3:42 PM"), animated: true)
        }
        for face in [view.currentFace, view.outgoingFace] {
            let opacity = try #require(springAnimation(on: face, "opacity"))
            #expect(abs(opacity.stiffness - ChatMotion.read.stiffness) < 0.001)
            #expect(abs(opacity.damping - ChatMotion.read.damping) < 0.001)
        }
        let enter = try #require((springAnimation(on: view.currentFace, "transform")?.fromValue as? NSValue)?.caTransform3DValue)
        #expect(abs(enter.m11 - ChatMotion.readEnterScale) < 0.0001)
        #expect(view.outgoingFace.alpha == 0)
    }

    @Test("Reset cancels a reveal in flight")
    func resetCancelsAReveal() {
        let view = makeView()
        view.setReceipt(.delivered, animated: true)
        view.reset()
        #expect(view.currentFace.layer.animationKeys() == nil)
        #expect(view.outgoingFace.layer.animationKeys() == nil)
    }
}
