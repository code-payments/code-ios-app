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
        #expect(ChatSwipeToReply.shouldBegin(velocity: CGPoint(x: 300, y: 40), isBlocked: false))
    }

    @Test("A mostly-vertical drag is left to the scroll view")
    func verticalDrag_doesNotBegin() {
        #expect(ChatSwipeToReply.shouldBegin(velocity: CGPoint(x: 40, y: -300), isBlocked: false) == false)
    }

    @Test("A diagonal drag with more vertical than horizontal is left to the scroll view")
    func diagonalDrag_doesNotBegin() {
        #expect(ChatSwipeToReply.shouldBegin(velocity: CGPoint(x: 120, y: -160), isBlocked: false) == false)
    }

    @Test("A drag towards the leading edge is not a reply swipe")
    func leadingDrag_doesNotBegin() {
        #expect(ChatSwipeToReply.shouldBegin(velocity: CGPoint(x: -300, y: 10), isBlocked: false) == false)
    }

    @Test("Nothing begins while the transcript is blocked")
    func blocked_doesNotBegin() {
        #expect(ChatSwipeToReply.shouldBegin(velocity: CGPoint(x: 300, y: 40), isBlocked: true) == false)
    }

    @Test("Translation past the maximum is bounded")
    func translation_isBounded() {
        let bound = ChatSwipeToReply.maxTranslation * 2
        #expect(ChatSwipeToReply.offset(forTranslation: 500) < bound)
        #expect(ChatSwipeToReply.offset(forTranslation: 5_000) < bound)
        // Bounded, but not a dead stop: a longer drag still moves the row further.
        #expect(ChatSwipeToReply.offset(forTranslation: 500) > ChatSwipeToReply.offset(forTranslation: 200))
    }

    @Test("A drag towards the leading edge does not move the row")
    func leadingTranslation_isIgnored() {
        #expect(ChatSwipeToReply.offset(forTranslation: -80) == 0)
    }

    @Test("Translation past the threshold resists")
    func translation_resistsPastThreshold() {
        let offset = ChatSwipeToReply.offset(forTranslation: 120)
        #expect(offset > ChatSwipeToReply.triggerThreshold)
        #expect(offset < 120)
    }

    @Test("Releasing past the threshold triggers the reply")
    func pastThreshold_triggers() {
        #expect(ChatSwipeToReply.triggers(offset: ChatSwipeToReply.triggerThreshold + 1))
    }

    @Test("Releasing short of the threshold does not trigger")
    func shortOfThreshold_doesNotTrigger() {
        #expect(ChatSwipeToReply.triggers(offset: ChatSwipeToReply.triggerThreshold - 1) == false)
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

    @Test("The arrow rests off the leading edge, out of frame")
    func arrow_restsOffTheEdge() {
        let center = ChatSwipeToReply.affordanceCenter(inRowOfHeight: 48)
        #expect(center.x < 0)
        #expect(center.y == 24)
    }

    @Test("The arrow rides the row into the gap the drag opens")
    func arrow_landsInsideTheRow() {
        let center = ChatSwipeToReply.affordanceCenter(inRowOfHeight: 48)
        // At full travel the row carries it back over the leading edge, clear of the bubble that
        // has moved out of the way by the same distance.
        let travelled = ChatSwipeToReply.affordanceCenter(
            inRowOfHeight: 48, offset: ChatSwipeToReply.maxTranslation
        ).x
        #expect(travelled > 0)
        #expect(travelled < ChatSwipeToReply.maxTranslation)
    }

    @Test("The arrow moves with the row, offset for offset")
    func arrow_tracksTheDrag() {
        let rest = ChatSwipeToReply.affordanceCenter(inRowOfHeight: 48).x
        let dragged = ChatSwipeToReply.affordanceCenter(inRowOfHeight: 48, offset: 30).x
        #expect(dragged - rest == 30)
    }
}

@Suite("Swipe offset on a row")
@MainActor
struct ChatColumnCellSwipeOffsetTests {

    private func laidOutCell() -> ChatMessageCell {
        let cell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 320, height: 60))
        cell.configure(with: ChatMessage(id: "1", text: "hi", sender: .me), maxWidth: 250)
        cell.layoutIfNeeded()
        return cell
    }

    private func bubbleX(_ cell: ChatMessageCell) -> CGFloat {
        cell.bubbleView.convert(cell.bubbleView.bounds, to: cell).minX
    }

    @Test("A swipe offset moves the row's content sideways")
    func offset_movesTheContent() {
        let cell = laidOutCell()
        let before = bubbleX(cell)
        cell.swipeOffset = 40
        #expect(bubbleX(cell) - before == 40)
    }

    @Test("A swipe offset survives a layout pass")
    func offset_survivesLayout() {
        // The regression this guards: the offset used to live on `contentView.transform`, which
        // `UICollectionViewCell.layoutSubviews` cancels by reassigning `contentView.frame` — so the
        // row read as motionless however far the finger travelled.
        let cell = laidOutCell()
        let before = bubbleX(cell)
        cell.swipeOffset = 40
        cell.setNeedsLayout()
        cell.layoutIfNeeded()
        #expect(bubbleX(cell) - before == 40)
    }

    @Test("Reuse clears the offset")
    func reuse_clearsTheOffset() {
        let cell = laidOutCell()
        let before = bubbleX(cell)
        cell.swipeOffset = 40
        cell.prepareForReuse()
        cell.layoutIfNeeded()
        #expect(cell.swipeOffset == 0)
        #expect(bubbleX(cell) == before)
    }
}

@Suite("Swipe offset in the live transcript")
@MainActor
struct ChatTranscriptSwipeOffsetTests {

    /// The cell-level test proves the offset survives `UICollectionViewCell.layoutSubviews`. This one
    /// proves it survives the layout that actually runs under it: ChatLayout re-measures self-sizing
    /// rows and writes cell frames, which is what cancelled the previous `contentView.transform`.
    @Test("The offset survives the transcript's own layout pass")
    func offset_survivesChatLayout() {
        let controller = ChatViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        window.rootViewController = controller
        window.isHidden = false
        controller.view.layoutIfNeeded()

        controller.update(
            items: (1...8).map { index in
                .message(ChatMessage(
                    id: "\(index)",
                    text: "message \(index)",
                    sender: index.isMultiple(of: 2) ? .me : .other
                ))
            },
            animated: false
        )
        controller.view.layoutIfNeeded()

        guard let cell = controller.collectionView.visibleCells.compactMap({ $0 as? ChatMessageCell }).first else {
            Issue.record("no bubble row on screen")
            return
        }
        let bubble = cell.bubbleView
        let before = bubble.convert(bubble.bounds, to: window).minX

        cell.swipeOffset = 40
        controller.collectionView.setNeedsLayout()
        controller.collectionView.layoutIfNeeded()

        #expect(abs(bubble.convert(bubble.bounds, to: window).minX - before - 40) < 0.5)
    }
}
