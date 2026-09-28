//
//  ChatReceiptView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI
import FlipcashCore

/// The "Delivered" / "Read 3:42 PM" line under the user's latest sent bubble.
///
/// Two overlaid faces rather than one label, because Delivered giving way to Read is a swap of two
/// pieces of text in the same place: the outgoing one shrinks away while the incoming one grows in,
/// and a single label can only cross-fade its own contents. `front` always holds the current line
/// and is the only face constrained to the view's edges, so the row's height follows it alone and
/// an exiting `back` never disturbs the layout.
final class ChatReceiptView: UIView {

    /// Resting color of the receipt line (Delivered/Read).
    static let defaultColor = UIColor.white.withAlphaComponent(0.5)
    /// Color of the failed status line: the theme's error-text token, which tracks appearance changes.
    static let failedColor = UIColor(Color.textError)
    /// Keeps the line off the column's trailing edge. Owned by the view rather than the face because
    /// the metadata row applies the same inset when the receipt is hidden and "Edited" stands alone —
    /// otherwise a lone marker sits 10pt further out than "Delivered" did.
    static let trailingPadding: CGFloat = 10

    private let front = ChatReceiptFace()
    private let back = ChatReceiptFace()

    /// The line currently shown, or nil when the row carries none.
    private(set) var currentReceipt: ChatReceipt?

    /// Where an animated clear leaves a fading copy of the line, or nil to clear instantly.
    ///
    /// The cell's content view: the metadata row collapses inside the same batch update, so a copy
    /// anywhere under it would be squeezed or clipped as the row closes.
    weak var exitHost: UIView?
    /// The copy of a just-cleared line still fading out in `exitHost`.
    private var exitGhost: ChatReceiptFace?

    override init(frame: CGRect) {
        super.init(frame: frame)
        // A row carries no line until one is set, and the whole column is the retry target, so the
        // line itself never takes touches.
        isHidden = true
        isUserInteractionEnabled = false

        // Back first, so the incoming face draws over the one it is replacing.
        for face in [back, front] {
            face.translatesAutoresizingMaskIntoConstraints = false
            addSubview(face)
        }
        back.isHidden = true

        NSLayoutConstraint.activate([
            front.topAnchor.constraint(equalTo: topAnchor),
            front.bottomAnchor.constraint(equalTo: bottomAnchor),
            front.leadingAnchor.constraint(equalTo: leadingAnchor),
            front.trailingAnchor.constraint(equalTo: trailingAnchor),
            // The outgoing face is positioned, never measured: it must not hold the row open while
            // it shrinks away.
            back.trailingAnchor.constraint(equalTo: trailingAnchor),
            back.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The column places this view; nothing animates it there. An arranged subview that un-hides
    /// inside the batch update's animation block otherwise springs in from the stack's origin, so the
    /// line would slide down across the bubble on its way to the gap under it. Suppressing the
    /// implicit geometry animation leaves the reveal as what it is meant to be: scale and opacity,
    /// in place. `transform` and `opacity` fall through to `super`, so the faces still animate.
    override func action(for layer: CALayer, forKey event: String) -> CAAction? {
        if layer === self.layer, event == "position" || event == "bounds" {
            return NSNull()
        }
        return super.action(for: layer, forKey: event)
    }

    /// Clears both faces and cancels any swap or exit in flight. Call from `prepareForReuse` — a
    /// recycled cell must not carry its previous row's line, or animate away from it.
    func reset() {
        exitGhost?.removeFromSuperview()
        exitGhost = nil
        clearFaces()
    }

    private func clearFaces() {
        layer.removeAllAnimations()
        front.layer.removeAllAnimations()
        back.layer.removeAllAnimations()
        currentReceipt = nil
        front.setReceipt(nil)
        front.transform = .identity
        front.alpha = 1
        back.setReceipt(nil)
        back.isHidden = true
        back.transform = .identity
        back.alpha = 1
        isHidden = true
    }

    /// Shows `receipt`, animating the change when `animated` is set.
    ///
    /// Three transitions, deliberately different: appearing from nothing is the slow, gentle
    /// `delivered` reveal; swapping one status for another is the quicker, bouncier `read` spring,
    /// with the old line shrinking out as the new one grows in; clearing empties this view at once,
    /// so the row collapses in step with the batch update, and leaves a copy of the line fading
    /// out in `exitHost` where it stood.
    func setReceipt(_ receipt: ChatReceipt?, animated: Bool) {
        guard receipt != currentReceipt else { return }
        let previous = currentReceipt
        currentReceipt = receipt

        guard let receipt else {
            let ghost = animated ? previous.flatMap(makeExitGhost(showing:)) : nil
            reset()
            if let ghost { fadeOut(ghost) }
            return
        }

        front.textColor = receipt.isFailed ? Self.failedColor : Self.defaultColor
        isHidden = false

        guard animated else {
            front.layer.removeAllAnimations()
            back.isHidden = true
            front.transform = .identity
            front.alpha = 1
            front.setReceipt(receipt)
            return
        }

        if let previous, previous.status != receipt.status {
            swap(from: previous, to: receipt)
        } else if previous == nil {
            reveal(receipt)
        } else {
            // Only the time moved (a re-render of the same Read line). Nothing to animate.
            front.setReceipt(receipt)
        }
    }

    /// nil → a line: grow in from `deliveredScale`.
    private func reveal(_ receipt: ChatReceipt) {
        UIView.performWithoutAnimation { front.setReceipt(receipt) }
        let start = scaled(ChatMotion.deliveredScale, width: front.fittingWidth)
        spring(front, on: ChatMotion.delivered, to: .identity, opacity: 1, from: start, opacity: 0)
    }

    /// Delivered → Read: the old line shrinks and fades out where it stands while the new one grows
    /// and fades in over it. The spec tunes both slide distances to zero, so this is scale and
    /// opacity only — the line stays put and changes.
    private func swap(from previous: ChatReceipt, to receipt: ChatReceipt) {
        UIView.performWithoutAnimation {
            back.textColor = previous.isFailed ? Self.failedColor : Self.defaultColor
            back.setReceipt(previous)
            back.isHidden = false
            front.setReceipt(receipt)
        }
        let backExit = scaled(ChatMotion.deliveredExitScale, width: back.fittingWidth)
        let frontStart = scaled(ChatMotion.readEnterScale, width: front.fittingWidth)

        CATransaction.begin()
        CATransaction.setCompletionBlock { [back] in
            // Also called when a newer swap replaces this one, which needs the face it just showed.
            guard back.layer.animation(forKey: Self.opacityKey) == nil else { return }
            back.isHidden = true
            back.transform = .identity
        }
        spring(back, on: ChatMotion.read, to: backExit, opacity: 0, from: .identity, opacity: 1)
        spring(front, on: ChatMotion.read, to: .identity, opacity: 1, from: frontStart, opacity: 0)
        CATransaction.commit()
    }

    private static let transformKey = "receipt.transform"
    private static let opacityKey = "receipt.opacity"

    /// Rests `face` at `transform` and `opacity`, springing there on `spring` from the starting pair.
    ///
    /// Core Animation rather than a `UIView` animation, because both transitions usually run inside
    /// the transcript's batch update: a `UIView` animation nested in that block rides the batch's
    /// spring instead of its own, and a start state assigned there is animated to rather than
    /// jumped to, so the scale-in cancels itself out. The resting values are set with animations
    /// off and the spring carries the face from the start, so no frame shows it at rest first.
    private func spring(
        _ face: ChatReceiptFace,
        on spring: ChatSpring,
        to transform: CGAffineTransform,
        opacity: CGFloat,
        from startTransform: CGAffineTransform,
        opacity startOpacity: CGFloat
    ) {
        UIView.performWithoutAnimation {
            face.transform = transform
            face.alpha = opacity
        }
        face.layer.add(
            spring.layerAnimation(
                keyPath: "transform",
                from: NSValue(caTransform3D: CATransform3DMakeAffineTransform(startTransform)),
                to: NSValue(caTransform3D: CATransform3DMakeAffineTransform(transform))
            ),
            forKey: Self.transformKey
        )
        face.layer.add(
            spring.layerAnimation(keyPath: "opacity", from: Float(startOpacity), to: Float(opacity)),
            forKey: Self.opacityKey
        )
    }

    /// A → nil: a copy of the line as it stands now, parked in `exitHost` over the spot this view is
    /// about to collapse out of, or nil when there is nowhere to put one.
    private func makeExitGhost(showing previous: ChatReceipt) -> ChatReceiptFace? {
        guard let host = exitHost, !isHidden, !front.bounds.isEmpty else { return nil }
        let ghost = ChatReceiptFace()
        // Called inside the batch update's animation block; the copy must appear where the line is,
        // not travel there.
        UIView.performWithoutAnimation {
            ghost.isUserInteractionEnabled = false
            ghost.textColor = front.textColor
            ghost.setReceipt(previous)
            ghost.bounds = front.bounds
            ghost.center = host.convert(CGPoint(x: front.bounds.midX, y: front.bounds.midY), from: front)
            // A line cleared mid-reveal leaves from the opacity it had reached, not from full.
            ghost.alpha = CGFloat(front.layer.presentation()?.opacity ?? Float(front.alpha))
            host.addSubview(ghost)
            ghost.layoutIfNeeded()
        }
        return ghost
    }

    /// Fades the copy out where it stands, then removes it. Opacity only: the line is leaving, not
    /// reacting, so it doesn't shrink.
    private func fadeOut(_ ghost: ChatReceiptFace) {
        exitGhost = ghost
        // Its own timing, not the batch update's spring it is called inside. A `UIView` animation
        // nested in a spring block rides that spring whatever its override options say, so the fade
        // is a Core Animation one: on the reflow spring the line lingered at half opacity under the
        // row gliding over it, then vanished when the fade's own duration ran out.
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = ghost.layer.opacity
        fade.toValue = 0
        fade.duration = ChatMotion.receiptExitFade
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            ghost.removeFromSuperview()
            if self?.exitGhost === ghost { self?.exitGhost = nil }
        }
        UIView.performWithoutAnimation { ghost.alpha = 0 }
        ghost.layer.add(fade, forKey: "exit")
        CATransaction.commit()
    }

    /// `scale` about the line's trailing edge (the text's, inside the face's padding), the edge it
    /// hugs, for a face `width` wide.
    ///
    /// The anchor rides in the transform rather than in `anchorPoint`, which would move the face.
    /// The width is passed in because a face revealed inside a batch update has not been laid out
    /// at its new size yet.
    private func scaled(_ scale: CGFloat, width: CGFloat) -> CGAffineTransform {
        let scaling = CGAffineTransform(scaleX: scale, y: scale)
        let edge = max(width / 2 - Self.trailingPadding, 0)
        let direction: CGFloat = effectiveUserInterfaceLayoutDirection == .rightToLeft ? -1 : 1
        return scaling.concatenating(CGAffineTransform(translationX: (1 - scale) * edge * direction, y: 0))
    }

    // MARK: - Test hooks

    /// The status run currently on the front face, or nil when the line is empty.
    var currentStatusText: String? { currentReceipt == nil ? nil : front.statusText }
    /// The timestamp run currently on the front face.
    var currentTimeText: String? { currentReceipt == nil ? nil : front.timeText }
    /// The status run on the back face — whatever is on its way out.
    var outgoingStatusText: String? { back.statusText }
    /// The front face's colour, which is what makes a failed line read as red.
    var currentColor: UIColor { front.textColor }
    /// The back face's colour — the outgoing state's, not the arriving one's.
    var outgoingColor: UIColor { back.textColor }
    /// The face holding the current line, which is the one a reveal or a swap animates in.
    var currentFace: UIView { front }
    /// The face holding the outgoing line during a swap.
    var outgoingFace: UIView { back }
    /// The copy of a cleared line still fading out in `exitHost`, or nil when none is.
    var fadingLine: UIView? { exitGhost }
    /// The status run on that fading copy.
    var fadingStatusText: String? { exitGhost?.statusText }
}

/// One rendering of a receipt line: the status in the heavier weight, the time in the lighter one.
///
/// Two labels rather than one attributed string because the pair is also a layout — a fixed gap
/// between the halves, and trailing padding that keeps the line off the column's edge.
private final class ChatReceiptFace: UIView {

    /// Gap between the status word and the time.
    private static let gap: CGFloat = 4
    private static let fontSize: CGFloat = 11

    private let status = ReceiptLabel()
    private let time = ReceiptLabel()
    private let row = ReceiptRow()

    var textColor: UIColor = ChatReceiptView.defaultColor {
        didSet {
            status.textColor = textColor
            time.textColor = textColor
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        status.font = .default(size: Self.fontSize, weight: .bold)
        time.font = .default(size: Self.fontSize, weight: .medium)
        for label in [status, time] {
            label.textColor = textColor
            label.numberOfLines = 1
        }

        row.axis = .horizontal
        row.spacing = Self.gap
        row.alignment = .firstBaseline
        row.addArrangedSubview(status)
        row.addArrangedSubview(time)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ChatReceiptView.trailingPadding),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Same reason as `ChatReceiptView`: the face is pinned to the receipt's edges, so it inherits
    /// that view's frame change and would travel with it.
    override func action(for layer: CALayer, forKey event: String) -> CAAction? {
        if layer === self.layer, event == "position" || event == "bounds" {
            return NSNull()
        }
        return super.action(for: layer, forKey: event)
    }

    func setReceipt(_ receipt: ChatReceipt?) {
        status.text = receipt?.status
        time.text = receipt?.time
        time.isHidden = receipt?.time == nil
    }

    var statusText: String? { status.text }
    var timeText: String? { time.isHidden ? nil : time.text }

    /// The width this face wants for the line it holds, trailing padding included.
    var fittingWidth: CGFloat {
        systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width
    }
}

// The face's insides refuse implicit geometry animation too. A line revealed inside a batch update
// is first laid out inside that update's animation, and its row and labels would otherwise grow from
// zero width, wiping the text in from the leading edge instead of letting the face's scale and fade
// be the whole reveal.

private final class ReceiptRow: UIStackView {
    override func action(for layer: CALayer, forKey event: String) -> CAAction? {
        if layer === self.layer, event == "position" || event == "bounds" {
            return NSNull()
        }
        return super.action(for: layer, forKey: event)
    }
}

private final class ReceiptLabel: UILabel {
    override func action(for layer: CALayer, forKey event: String) -> CAAction? {
        if layer === self.layer, event == "position" || event == "bounds" {
            return NSNull()
        }
        return super.action(for: layer, forKey: event)
    }
}
#endif
