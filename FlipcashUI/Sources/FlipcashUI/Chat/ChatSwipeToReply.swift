//
//  ChatSwipeToReply.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit

/// Drag a row towards the trailing edge to reply to it.
///
/// Owns the whole gesture — the recognizer, the row being dragged, its offset, and whether the
/// trigger has already fired — because those four move together and splitting them across the
/// transcript's fields would make the coexistence rules impossible to follow. The transcript keeps
/// one `let` and answers two questions: which row is under a point, and whether it can be replied to.
@MainActor
final class ChatSwipeToReply: NSObject {

    /// Furthest a row travels. Past this the drag resists rather than stopping dead, so a hard
    /// swipe still feels connected to the finger.
    nonisolated static let maxTranslation: CGFloat = 64
    /// Offset at which the reply fires, mid-drag.
    nonisolated static let triggerThreshold: CGFloat = 48
    /// Width of the leading strip left to the system's interactive-pop gesture. The reply swipe runs
    /// in the same direction as back-navigation, so the two would otherwise fight over every drag
    /// that starts at the screen edge — and the row would win, leaving no way back.
    nonisolated static let backGestureInset: CGFloat = 24
    /// Where the affordance comes to rest at full travel, measured from the row's leading edge.
    nonisolated private static let affordanceInset: CGFloat = 20
    nonisolated private static let affordanceDiameter: CGFloat = 32

    let recognizer = UIPanGestureRecognizer()

    /// The row under a point, if it can be replied to. The transcript answers this; the gesture
    /// does not know what a message is.
    var rowForSwipe: ((CGPoint) -> (cell: ChatColumnCell, stableID: String)?)?
    /// Whether the transcript is busy — mid-update, or showing a context menu.
    var isBlocked: (() -> Bool)?
    /// Called once, when the drag crosses the threshold.
    var onTrigger: ((String) -> Void)?

    private var draggedCell: ChatColumnCell?
    private var draggedStableID: String?
    /// Latched for the rest of the drag once the threshold fires, so the reply is sent once and the
    /// row does not re-follow a finger that is still moving after it has sprung back. Reset in
    /// `begin`, not in `settle` — `settle` also runs on the trigger itself.
    private var hasTriggered = false
    private let affordance = UIView()
    private let affordanceIcon = UIImageView()
    private let haptics = UIImpactFeedbackGenerator(style: .light)

    override init() {
        super.init()
        recognizer.addTarget(self, action: #selector(handlePan))
        recognizer.delegate = self
        recognizer.maximumNumberOfTouches = 1

        affordance.bounds = CGRect(x: 0, y: 0, width: Self.affordanceDiameter, height: Self.affordanceDiameter)
        affordance.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        affordance.layer.cornerRadius = Self.affordanceDiameter / 2
        affordance.alpha = 0

        affordanceIcon.image = UIImage(systemName: SystemSymbol.replyArrow.rawValue)
        affordanceIcon.tintColor = UIColor.white.withAlphaComponent(0.75)
        affordanceIcon.contentMode = .scaleAspectFit
        affordanceIcon.frame = affordance.bounds.insetBy(dx: 8, dy: 8)
        affordance.addSubview(affordanceIcon)
    }

    /// Whether a drag with this velocity is a reply swipe rather than a scroll.
    ///
    /// Horizontal dominance is the whole rule: a diagonal drag belongs to the scroll view, which
    /// would otherwise lose it to a recognizer that only ever moves sideways. Only trailing-ward
    /// drags qualify — the leading direction is left free for anything that wants it later.
    nonisolated static func shouldBegin(velocity: CGPoint, isBlocked: Bool) -> Bool {
        guard !isBlocked else { return false }
        guard velocity.x > 0 else { return false }
        return abs(velocity.x) > abs(velocity.y)
    }

    /// Whether a drag starting at this x belongs to back-navigation rather than to the row. Kept
    /// separate from `shouldBegin` because it is a rule about where the finger landed, not about
    /// which way it moved, and the two fail for different reasons.
    nonisolated static func defersToBackGesture(startX: CGFloat) -> Bool {
        startX < backGestureInset
    }

    /// How far the row actually moves for a raw translation: clamped, with resistance past the max.
    nonisolated static func offset(forTranslation translation: CGFloat) -> CGFloat {
        guard translation > 0 else { return 0 }
        guard translation > maxTranslation else { return translation }
        // Rubber band: past the max the row keeps following the finger, but with diminishing
        // returns that approach one more `maxTranslation` of travel and never exceed it — so a hard
        // swipe still feels connected without running the row off under the bubble beside it.
        let overshoot = translation - maxTranslation
        return maxTranslation + maxTranslation * overshoot / (overshoot + maxTranslation)
    }

    /// Whether this offset fires the reply. Consulted mid-drag: crossing the threshold sends,
    /// without waiting for the finger to lift.
    nonisolated static func triggers(offset: CGFloat) -> Bool {
        offset > triggerThreshold
    }

    /// Where the affordance sits in the row's own coordinates at a given drag offset. It starts off
    /// the leading edge and rides the row by the same offset the row moves, which is why it needs no
    /// knowledge of which edge the bubble hugs: at rest it is out of frame for either sender, and at
    /// full travel it lands in space the bubble has just left.
    ///
    /// The offset is carried here rather than in a transform because the affordance's transform is
    /// spent on the scale, and it is parented to the content view rather than to the column the row's
    /// own translation moves.
    nonisolated static func affordanceCenter(inRowOfHeight height: CGFloat, offset: CGFloat = 0) -> CGPoint {
        CGPoint(x: affordanceInset + affordanceDiameter / 2 - maxTranslation + offset, y: height / 2)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            begin(at: gesture.location(in: gesture.view))
        case .changed:
            guard !hasTriggered else { return }
            let offset = Self.offset(forTranslation: gesture.translation(in: gesture.view).x)
            apply(offset: offset)
            // The reply fires here rather than from `.ended`, because a gesture that waits for the
            // finger to lift spends the whole hold doing nothing visible and reads as lag — on a
            // measured drag the row sat pinned at full travel for half a second before the release
            // that finally mounted the strip. Sending at the threshold puts the strip and the
            // keyboard up while the finger is still down, which is what every other messenger does.
            guard Self.triggers(offset: offset) else { return }
            hasTriggered = true
            haptics.impactOccurred()
            let stableID = draggedStableID
            // Spring the row back now: it has done its job, and leaving it parked under a finger
            // that has already sent would ask the user to release before they see the result.
            settle()
            if let stableID { onTrigger?(stableID) }
        case .ended, .cancelled, .failed:
            settle()
        case .possible, .recognized:
            break
        @unknown default:
            settle()
        }
    }

    private func begin(at point: CGPoint) {
        guard let row = rowForSwipe?(point) else {
            recognizer.state = .cancelled
            return
        }
        draggedCell = row.cell
        draggedStableID = row.stableID
        hasTriggered = false
        haptics.prepare()

        affordance.alpha = 0
        affordance.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        affordance.center = Self.affordanceCenter(inRowOfHeight: row.cell.bounds.height)
        row.cell.contentView.addSubview(affordance)
    }

    private func apply(offset: CGFloat) {
        guard let draggedCell else { return }
        draggedCell.swipeOffset = offset
        // The arrow rides the row by the same offset, and grows in over the run-up to the trigger, so
        // the gesture announces itself before it fires rather than after.
        let progress = min(1, offset / Self.triggerThreshold)
        affordance.center = Self.affordanceCenter(inRowOfHeight: draggedCell.bounds.height, offset: offset)
        affordance.alpha = progress
        affordance.transform = CGAffineTransform(scaleX: 0.6 + 0.4 * progress, y: 0.6 + 0.4 * progress)
    }

    private func settle() {
        let cell = draggedCell
        let restingCenter = Self.affordanceCenter(inRowOfHeight: cell?.bounds.height ?? 0)
        draggedCell = nil
        draggedStableID = nil
        ChatMotion.swap.animate {
            cell?.swipeOffset = 0
            self.affordance.center = restingCenter
            self.affordance.alpha = 0
            self.affordance.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        } completion: { _ in
            // Only when no newer drag has claimed it: the arrow is one shared view, so an unguarded
            // removal here tears it out of the row a second swipe has already started on.
            if self.draggedCell == nil { self.affordance.removeFromSuperview() }
        }
    }
}

extension ChatSwipeToReply: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
        guard Self.shouldBegin(velocity: pan.velocity(in: pan.view), isBlocked: isBlocked?() ?? false) else {
            return false
        }
        // Measured against the window, not the scroll view: the row's own x origin drifts with the
        // transform of whatever is mid-settle, and the strip we are avoiding is a screen edge.
        let edgeReference = pan.view?.window ?? pan.view
        guard !Self.defersToBackGesture(startX: pan.location(in: edgeReference).x) else { return false }
        return rowForSwipe?(pan.location(in: pan.view)) != nil
    }
}
#endif
