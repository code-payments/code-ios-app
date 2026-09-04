//
//  ChatSwipeToReplyTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI

@Suite("Swipe to reply")
@MainActor
struct ChatSwipeToReplyTests {

    @Test("A mostly-horizontal drag may begin")
    func horizontalDrag_begins() {
        #expect(ChatSwipeToReply.shouldBegin(velocity: CGPoint(x: -300, y: 40), isBlocked: false))
    }

    @Test("A mostly-vertical drag is left to the scroll view")
    func verticalDrag_doesNotBegin() {
        #expect(ChatSwipeToReply.shouldBegin(velocity: CGPoint(x: -40, y: -300), isBlocked: false) == false)
    }

    @Test("A diagonal drag with more vertical than horizontal is left to the scroll view")
    func diagonalDrag_doesNotBegin() {
        #expect(ChatSwipeToReply.shouldBegin(velocity: CGPoint(x: 120, y: -160), isBlocked: false) == false)
    }

    @Test("A drag towards the trailing edge is not a reply swipe")
    func trailingDrag_doesNotBegin() {
        #expect(ChatSwipeToReply.shouldBegin(velocity: CGPoint(x: 300, y: 10), isBlocked: false) == false)
    }

    @Test("Nothing begins while the transcript is blocked")
    func blocked_doesNotBegin() {
        #expect(ChatSwipeToReply.shouldBegin(velocity: CGPoint(x: -300, y: 40), isBlocked: true) == false)
    }

    @Test("Translation past the maximum is bounded")
    func translation_isBounded() {
        let bound = -ChatSwipeToReply.maxTranslation * 2
        #expect(ChatSwipeToReply.offset(forTranslation: -500) > bound)
        #expect(ChatSwipeToReply.offset(forTranslation: -5_000) > bound)
        // Bounded, but not a dead stop: a longer drag still moves the row further.
        #expect(ChatSwipeToReply.offset(forTranslation: -500) < ChatSwipeToReply.offset(forTranslation: -200))
    }

    @Test("A drag towards the trailing edge does not move the row")
    func trailingTranslation_isIgnored() {
        #expect(ChatSwipeToReply.offset(forTranslation: 80) == 0)
    }

    @Test("Translation past the threshold resists")
    func translation_resistsPastThreshold() {
        let offset = ChatSwipeToReply.offset(forTranslation: -120)
        #expect(offset < -ChatSwipeToReply.triggerThreshold)
        #expect(offset > -120)
    }

    @Test("Crossing the threshold triggers the reply")
    func pastThreshold_triggers() {
        #expect(ChatSwipeToReply.triggers(offset: -ChatSwipeToReply.triggerThreshold - 1))
    }

    @Test("Releasing short of the threshold does not trigger")
    func shortOfThreshold_doesNotTrigger() {
        #expect(ChatSwipeToReply.triggers(offset: -ChatSwipeToReply.triggerThreshold + 1) == false)
    }

    @Test("A drag starting on the leading edge is left to back-navigation")
    func leadingEdgeDrag_defersToBack() {
        #expect(ChatSwipeToReply.defersToBackGesture(startX: 0))
        #expect(ChatSwipeToReply.defersToBackGesture(startX: ChatSwipeToReply.backGestureInset - 1))
    }

    @Test("A drag starting anywhere else on the row is a reply swipe")
    func restOfRow_doesNotDeferToBack() {
        #expect(ChatSwipeToReply.defersToBackGesture(startX: ChatSwipeToReply.backGestureInset) == false)
        // The empty space beside a bubble is as swipeable as the bubble itself.
        #expect(ChatSwipeToReply.defersToBackGesture(startX: 120) == false)
        #expect(ChatSwipeToReply.defersToBackGesture(startX: 380) == false)
    }

    @Test("The edge left to back-navigation is a strip, not a third of the row")
    func backGestureInset_staysNarrow() {
        #expect(ChatSwipeToReply.backGestureInset < 40)
    }

    @Test("A self message's arrow hangs in the empty leading space")
    func selfMessage_arrowLeads() {
        let center = ChatSwipeToReply.affordanceCenter(inRowOfWidth: 390, height: 48, isFromSelf: true)
        #expect(center.x < 390 / 2)
        #expect(center.y == 24)
    }

    @Test("An incoming message's arrow hangs in the empty trailing space")
    func otherMessage_arrowTrails() {
        let center = ChatSwipeToReply.affordanceCenter(inRowOfWidth: 390, height: 48, isFromSelf: false)
        #expect(center.x > 390 / 2)
    }

    @Test("The arrow sits clear of both row edges")
    func arrow_clearsTheEdges() {
        let width: CGFloat = 390
        for isFromSelf in [true, false] {
            let center = ChatSwipeToReply.affordanceCenter(inRowOfWidth: width, height: 48, isFromSelf: isFromSelf)
            #expect(center.x > 0)
            #expect(center.x < width)
        }
    }
}
