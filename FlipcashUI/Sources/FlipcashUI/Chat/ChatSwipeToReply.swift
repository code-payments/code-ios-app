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

    let recognizer = UIPanGestureRecognizer()

    /// The row under a point, if it can be replied to. The transcript answers this; the gesture
    /// does not know what a message is.
    var rowForSwipe: ((CGPoint) -> (cell: UICollectionViewCell, stableID: String)?)?
    /// Whether the transcript is busy — mid-update, or showing a context menu.
    var isBlocked: (() -> Bool)?
    /// Called once, when the drag crosses the threshold.
    var onTrigger: ((String) -> Void)?

    private var draggedCell: UICollectionViewCell?
    private var draggedStableID: String?
    private var hasTriggered = false
    private let affordance = UIImageView()
    private let haptics = UIImpactFeedbackGenerator(style: .light)

    override init() {
        super.init()
        recognizer.addTarget(self, action: #selector(handlePan))
        recognizer.delegate = self
        recognizer.maximumNumberOfTouches = 1

        affordance.image = UIImage(systemName: SystemSymbol.replyArrow.rawValue)
        affordance.tintColor = UIColor.white.withAlphaComponent(0.55)
        affordance.contentMode = .scaleAspectFit
        affordance.alpha = 0
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
        affordance.frame = CGRect(
            x: row.cell.bounds.width - 34,
            y: (row.cell.bounds.height - 20) / 2,
            width: 20,
            height: 20
        )
        row.cell.contentView.addSubview(affordance)
    }

    private func apply(offset: CGFloat) {
        guard let draggedCell else { return }
        draggedCell.contentView.transform = CGAffineTransform(translationX: offset, y: 0)
        // The arrow fades in over the run-up to the trigger, so the gesture announces itself before
        // it fires rather than after.
        affordance.alpha = min(1, -offset / Self.triggerThreshold)
    }

    private func settle() {
        let cell = draggedCell
        draggedCell = nil
        draggedStableID = nil
        hasTriggered = false
        ChatMotion.swap.animate {
            cell?.contentView.transform = .identity
            self.affordance.alpha = 0
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
        return rowForSwipe?(pan.location(in: pan.view)) != nil
    }
}
#endif
