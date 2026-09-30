//
//  MessageLiftGestureTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
@testable import FlipcashUI

@Suite("Message lift gestures")
@MainActor
struct MessageLiftGestureTests {

    @Test("The transcript's long press doesn't run beside a tap, so a lift never also fires the tap")
    func longPress_isExclusiveOfTaps() throws {
        let transcript = ChatViewController()
        transcript.loadViewIfNeeded()
        let press = try #require(transcript.collectionView.gestureRecognizers?.first {
            $0 is UILongPressGestureRecognizer && $0.delegate === transcript
        })
        #expect(transcript.gestureRecognizer(press, shouldRecognizeSimultaneouslyWith: UITapGestureRecognizer()) == false)
        #expect(transcript.gestureRecognizer(UITapGestureRecognizer(), shouldRecognizeSimultaneouslyWith: press) == false)
    }

    @Test("A link bubble's tap stands down for a long press but still runs beside the keyboard's tap")
    func linkTap_standsDownForLongPress() {
        let bubble = LinkableBubbleView()
        let tap = UITapGestureRecognizer()
        #expect(bubble.gestureRecognizer(tap, shouldRecognizeSimultaneouslyWith: UILongPressGestureRecognizer()) == false)
        #expect(bubble.gestureRecognizer(tap, shouldRecognizeSimultaneouslyWith: UITapGestureRecognizer()))
    }

    @Test("A finger that hasn't moved since the press can't choose a row the menu opened under it")
    func stillFinger_isNotAdmitted() {
        var gate = LiftDragGate(origin: CGPoint(x: 300, y: 780))
        let admitted = gate.admits(CGPoint(x: 302, y: 783))
        #expect(admitted == false)
    }

    @Test("Once the finger drags away from the press, it tracks the menu, even back over the start")
    func draggedFinger_isAdmitted() {
        var gate = LiftDragGate(origin: CGPoint(x: 300, y: 780))
        let away = gate.admits(CGPoint(x: 300, y: 780 + LiftDragGate.threshold + 1))
        let back = gate.admits(CGPoint(x: 300, y: 780))
        #expect(away)
        #expect(back)
    }
}
