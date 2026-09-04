//
//  ChatSwipeToReply.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit

/// Drag a row towards the leading edge to reply to it.
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
    /// Offset at which the reply fires on release.
    nonisolated static let triggerThreshold: CGFloat = 48
    /// Width of the leading strip left to the system's interactive-pop gesture. A swipe is a
    /// whole-row gesture everywhere else, but a drag that starts inside this strip belongs to
    /// back-navigation, and claiming it means the row moves instead of the screen.
    nonisolated static let backGestureInset: CGFloat = 24
    /// How far the affordance sits from the row edge it hangs off.
    nonisolated private static let affordanceInset: CGFloat = 20
    nonisolated private static let affordanceDiameter: CGFloat = 32

    let recognizer = UIPanGestureRecognizer()

    /// The row under a point, if it can be replied to, and which side its bubble hugs. The
    /// transcript answers this; the gesture does not know what a message is.
    var rowForSwipe: ((CGPoint) -> (cell: UICollectionViewCell, stableID: String, isFromSelf: Bool)?)?
    /// Whether the transcript is busy — mid-update, or showing a context menu.
    var isBlocked: (() -> Bool)?
    /// Called once, when the drag crosses the threshold.
    var onTrigger: ((String) -> Void)?

    private var draggedCell: UICollectionViewCell?
    private var draggedStableID: String?
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
    /// would otherwise lose it to a recognizer that only ever moves sideways. Only leading-ward
    /// drags qualify — the trailing direction is left free for anything that wants it later.
    nonisolated static func shouldBegin(velocity: CGPoint, isBlocked: Bool) -> Bool {
        guard !isBlocked else { return false }
        guard velocity.x < 0 else { return false }
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
        guard translation < 0 else { return 0 }
        let distance = -translation
        guard distance > maxTranslation else { return translation }
        // Rubber band: past the max the row keeps following the finger, but with diminishing
        // returns that approach one more `maxTranslation` of travel and never exceed it — so a hard
        // swipe still feels connected without running the row off under the bubble beside it.
        let overshoot = distance - maxTranslation
        return -(maxTranslation + maxTranslation * overshoot / (overshoot + maxTranslation))
    }

    /// Whether releasing at this offset fires the reply.
    nonisolated static func triggers(offset: CGFloat) -> Bool {
        offset < -triggerThreshold
    }

    /// Where the affordance hangs, in the row's own coordinates. It goes on the side the bubble
    /// does *not* occupy — a self message hugs the trailing edge, so its arrow belongs in the empty
    /// leading space, and anchoring both to the trailing edge draws the arrow over the bubble.
    nonisolated static func affordanceCenter(inRowOfWidth width: CGFloat, height: CGFloat, isFromSelf: Bool) -> CGPoint {
        let x = isFromSelf
            ? affordanceInset + affordanceDiameter / 2
            : width - affordanceInset - affordanceDiameter / 2
        return CGPoint(x: x, y: height / 2)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            begin(at: gesture.location(in: gesture.view))
        case .changed:
            let offset = Self.offset(forTranslation: gesture.translation(in: gesture.view).x)
            apply(offset: offset)
            if !hasTriggered, Self.triggers(offset: offset) {
                hasTriggered = true
                haptics.impactOccurred()
                if let draggedStableID { onTrigger?(draggedStableID) }
            }
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
        affordance.transform = .identity
        affordance.center = Self.affordanceCenter(
            inRowOfWidth: row.cell.bounds.width,
            height: row.cell.bounds.height,
            isFromSelf: row.isFromSelf
        )
        row.cell.contentView.addSubview(affordance)
    }

    private func apply(offset: CGFloat) {
        guard let draggedCell else { return }
        draggedCell.contentView.transform = CGAffineTransform(translationX: offset, y: 0)
        // The arrow grows in over the run-up to the trigger, so the gesture announces itself before
        // it fires rather than after.
        let progress = min(1, -offset / Self.triggerThreshold)
        affordance.alpha = progress
        affordance.transform = CGAffineTransform(scaleX: 0.6 + 0.4 * progress, y: 0.6 + 0.4 * progress)
    }

    private func settle() {
        let cell = draggedCell
        draggedCell = nil
        draggedStableID = nil
        hasTriggered = false
        ChatMotion.swap.animate {
            cell?.contentView.transform = .identity
            self.affordance.alpha = 0
            self.affordance.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        } completion: { _ in
            self.affordance.removeFromSuperview()
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
