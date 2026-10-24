//
//  ChatTimestampReveal.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit

/// Drag the transcript towards the leading edge to reveal every message's send time.
///
/// One offset for the whole transcript, not one row: every visible row reads it, sent bubbles slide
/// left by it and the time column rides in from the trailing edge. It runs the opposite way to
/// `ChatSwipeToReply`, so a drag commits to one or the other by its direction. Nothing fires on
/// release — no threshold, no haptic; the transcript springs back.
@MainActor
final class ChatTimestampReveal: NSObject {

    /// Width of the time column; the label is right-aligned in it.
    nonisolated static let columnWidth: CGFloat = 64

    /// Gap between the time column and the row's trailing edge.
    nonisolated static let trailingMargin: CGFloat = 12

    /// The furthest a sent bubble travels: the column plus its margin, so the bubble's trailing
    /// edge stops one margin short of the time.
    nonisolated static let travel: CGFloat = columnWidth + trailingMargin

    let recognizer = UIPanGestureRecognizer()

    /// Whether the transcript is busy — mid-update, or showing a context menu.
    var isBlocked: (() -> Bool)?
    /// Called with the new offset on every frame of the drag, and once inside the settle animation.
    var onOffsetChange: ((CGFloat) -> Void)?

    /// The current reveal offset, for a row that is dequeued mid-drag.
    private(set) var offset: CGFloat = 0

    override init() {
        super.init()
        recognizer.addTarget(self, action: #selector(handlePan))
        recognizer.delegate = self
        recognizer.maximumNumberOfTouches = 1
    }

    /// Whether a drag with this velocity reveals times rather than scrolling or replying.
    ///
    /// Leading-ward and horizontally dominant: the trailing direction is the reply swipe's.
    nonisolated static func shouldBegin(velocity: CGPoint, isBlocked: Bool) -> Bool {
        guard !isBlocked else { return false }
        guard velocity.x < 0 else { return false }
        return abs(velocity.x) > abs(velocity.y)
    }

    /// How far the sent bubbles move for a raw translation: follows the finger for half of
    /// `travel`, then resists, and never passes `travel`.
    nonisolated static func offset(forTranslation translation: CGFloat) -> CGFloat {
        let drag = -translation
        guard drag > 0 else { return 0 }
        let linear = travel / 2
        guard drag > linear else { return drag }
        // The same rubber band as the reply swipe: approaches one more `linear` of travel, so the
        // whole of `travel`, without reaching it.
        let overshoot = drag - linear
        return min(travel, linear + linear * overshoot / (overshoot + linear))
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            apply(offset: Self.offset(forTranslation: gesture.translation(in: gesture.view).x))
        case .ended, .cancelled, .failed:
            settle()
        case .possible, .recognized:
            break
        @unknown default:
            settle()
        }
    }

    private func apply(offset: CGFloat) {
        self.offset = offset
        onOffsetChange?(offset)
    }

    private func settle() {
        offset = 0
        ChatMotion.swap.animate {
            self.onOffsetChange?(0)
        }
    }
}

extension ChatTimestampReveal: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
        return Self.shouldBegin(velocity: pan.velocity(in: pan.view), isBlocked: isBlocked?() ?? false)
    }
}
#endif
