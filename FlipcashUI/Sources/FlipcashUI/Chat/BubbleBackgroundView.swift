//
//  BubbleBackgroundView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI

/// The shared chrome behind every chat bubble and cash card: a white-opacity wash over the
/// conversation background, with a hairline border and a continuous, per-corner rounded shape.
///
/// The wash is composited here, over an opaque base, rather than left as a translucent
/// `backgroundColor`. A translucent bubble takes the colour of whatever happens to be behind it, and
/// that is not always the transcript: a context menu dims what it covers and an edit blurs it, and
/// both showed straight through, leaving one message reading three different ways. Carrying its own
/// ground, it renders the same in all three.
///
/// A bubble run flattens the inner corners
/// from `baseRadius` to `groupedRadius`, which UIKit's `cornerCurve`/`maskedCorners` can't express,
/// so the path is taken straight from SwiftUI's `UnevenRoundedRectangle(.continuous)` (pure geometry,
/// no hosted SwiftUI views) and drawn into a `CAShapeLayer`.
final class BubbleBackgroundView: UIView {

    /// Base corner radius; the inner corner of a grouped run uses `groupedRadius`.
    static let baseRadius: CGFloat = 12
    static let groupedRadius: CGFloat = 4

    private let shapeMask = CAShapeLayer()
    private let washLayer = CALayer()
    private let attentionLayer = CALayer()
    private let borderLayer = CAShapeLayer()
    private var radii = RectangleCornerRadii(topLeading: baseRadius, bottomLeading: baseRadius, bottomTrailing: baseRadius, topTrailing: baseRadius)
    /// The message this chrome currently draws, so a radii change can be told apart from a recycled
    /// view being set up for a different row. A view with no identity never morphs.
    private var identity: String?
    /// Set by `apply` when the radii changed in place; consumed by the next `layoutSubviews`, which
    /// is where the path is actually built.
    private var pendingCornerMorph = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.mask = shapeMask
        backgroundColor = UIColor(Color.backgroundMain)
        // Resized in `layoutSubviews`, where an implicit animation would drag a block of solid
        // colour behind the bubble's own frame change.
        washLayer.actions = ["position": NSNull(), "bounds": NSNull(), "hidden": NSNull()]
        layer.addSublayer(washLayer)
        // Above the wash and below the border, so the flash brightens the bubble's ground without
        // washing over its text or softening its hairline edge.
        attentionLayer.backgroundColor = Self.attentionWash.cgColor
        attentionLayer.opacity = 0
        attentionLayer.actions = ["position": NSNull(), "bounds": NSNull()]
        layer.addSublayer(attentionLayer)
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.strokeColor = UIColor.white.withAlphaComponent(0.03).cgColor
        borderLayer.lineWidth = 1
        borderLayer.actions = ["position": NSNull(), "bounds": NSNull(), "hidden": NSNull()]
        layer.addSublayer(borderLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // Bare mode swaps `backgroundColor` to clear, and a reconfigure inside a batch update is an
    // animation context — without this the base cross-fades while the row is moving. This must be a
    // delegate override, not `layer.actions`: `CALayer.action(for:forKey:)` asks the delegate (this
    // view) first, and `UIView`'s own answer for `backgroundColor` always wins over the layer's own
    // dictionary. The `layer === self.layer` check matters — this view has four sublayers, and they
    // must keep falling through to their own `actions` dictionaries.
    override func action(for layer: CALayer, forKey event: String) -> CAAction? {
        if layer === self.layer, event == "backgroundColor" {
            return NSNull()
        }
        return super.action(for: layer, forKey: event)
    }

    /// Sets the chrome. `identity` is the row this is drawing — pass it, and a later `apply` for the
    /// same row that changes the radii morphs the corner instead of snapping it. A first setup, a
    /// recycled view taking a new row, and any caller that passes no identity all snap, which is what
    /// keeps a reused cell from animating in someone else's shape.
    ///
    /// `bare` draws no bubble at all, for a row that is only its content.
    func apply(fill: UIColor, radii: RectangleCornerRadii, bare: Bool = false, identity: String? = nil) {
        // The opaque base goes too, not just the wash and the border: it is there so a bubble reads
        // the same under the context menu's dim and the edit blur, and behind a bare row the same
        // base would be a rectangular patch against both.
        backgroundColor = bare ? .clear : UIColor(Color.backgroundMain)
        washLayer.isHidden = bare
        borderLayer.isHidden = bare
        washLayer.backgroundColor = fill.cgColor
        // A recycled view taking a new row drops any flash still running, so the attention never
        // finishes on a message it wasn't meant for.
        if identity != self.identity {
            attentionLayer.removeAnimation(forKey: Self.attentionKey)
        }
        pendingCornerMorph = identity != nil && identity == self.identity && radii != self.radii
        self.identity = identity
        self.radii = radii
        setNeedsLayout()
    }

    /// Whether this chrome draws a bubble: the opaque base, the wash and the hairline border. False
    /// for a bare row, which keeps only the shape mask and the attention layer — the mask because
    /// an unclipped flash would be a rectangle floating where no bubble is.
    var isDrawingBubble: Bool { !washLayer.isHidden }

    /// The bubble's continuous, per-corner rounded shape in its own coordinate space — the same
    /// geometry used for the layer mask. Clips the context-menu lift preview to the bubble.
    var maskingPath: UIBezierPath {
        UIBezierPath(cgPath: UnevenRoundedRectangle(cornerRadii: radii, style: .continuous).path(in: bounds).cgPath)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let previous = shapeMask.path
        let path = UnevenRoundedRectangle(cornerRadii: radii, style: .continuous).path(in: bounds).cgPath
        shapeMask.path = path
        washLayer.frame = bounds
        attentionLayer.frame = bounds
        borderLayer.path = path
        borderLayer.frame = bounds

        // A `CAShapeLayer`'s `path` isn't animatable through `UIView.animate`, so the corner morph is
        // its own explicit spring. It's the slowest in the vocabulary on purpose: a quiet detail
        // playing underneath the faster insertion.
        guard pendingCornerMorph, let previous else { return }
        pendingCornerMorph = false
        for layer in [shapeMask, borderLayer] {
            layer.add(ChatMotion.corner.layerAnimation(keyPath: "path", from: previous, to: path), forKey: "cornerMorph")
        }
    }

    // MARK: - Attention

    private static let attentionKey = "attention"

    /// Brightens the bubble's ground for `ChatMotion.attentionDuration`, then lets it fade back.
    ///
    /// Runs as a keyframe on the layer rather than a `UIView` animation because the resting opacity
    /// must stay 0 throughout: the row can be reconfigured or recycled mid-flash, and a model value
    /// left raised would strand a lit bubble.
    ///
    /// `start` is when the flash began, in `CACurrentMediaTime()`'s clock. Passing a time already
    /// past joins a flash in progress rather than restarting it, so a row re-dequeued mid-flash
    /// picks it up where it left off and still ends when it would have.
    func flashAttention(startedAt start: CFTimeInterval = CACurrentMediaTime()) {
        let rise = ChatMotion.attentionRise
        let hold = ChatMotion.attentionHold
        let total = ChatMotion.attentionDuration
        let flash = CAKeyframeAnimation(keyPath: "opacity")
        flash.values = [0, 1, 1, 0]
        flash.keyTimes = [0, NSNumber(value: rise / total), NSNumber(value: (rise + hold) / total), 1]
        flash.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .linear),
            CAMediaTimingFunction(name: .easeInEaseOut),
        ]
        flash.duration = total
        flash.beginTime = start
        attentionLayer.removeAnimation(forKey: Self.attentionKey)
        attentionLayer.add(flash, forKey: Self.attentionKey)
    }

    /// Whether an attention flash is currently running on this chrome.
    var isFlashingAttention: Bool { attentionLayer.animation(forKey: Self.attentionKey) != nil }

    /// The lift the flash adds on top of the sender's resting wash. Sized to read on both fills —
    /// a received bubble sits at 0.02 white, so the same absolute lift is the larger relative jump
    /// there, which is right: the message being pointed at is usually the other person's.
    private static let attentionWash = UIColor.white.withAlphaComponent(0.10)

    /// The elevation a bubble sits at once it has been lifted out of the transcript.
    ///
    /// Set by hand rather than left to UIKit. A `UITargetedPreview` built with a clear background
    /// casts nothing — with or without `shadowPath` — so the menu arrived with the lifted message
    /// flat against the transcript, measured at rgb 17 right up to its edge on all sides. Owning the
    /// values here also means the menu's lift and the edit that follows it share one shadow rather
    /// than one of them guessing at a system default the other inherited.
    private static let liftShadowOpacity: Float = 0.65
    private static let liftShadowRadius: CGFloat = 20
    private static let liftShadowOffset = CGSize(width: 0, height: 10)

    /// Raises `view` to the lifted plane. `shape` is the bubble's own path, so the shadow follows a
    /// flattened grouped corner instead of falling back to the view's square bounds. `nil` — a bare
    /// row, with no bubble to trace — casts no shadow at all, rather than one Core Animation derives
    /// from the view's rendered alpha: a clear-backgrounded preview's only opaque content is its
    /// emoji, and an undirected shadow would trace that glyph instead of reading as chromeless.
    ///
    /// Applied to the view *hosting* the chrome, never to this view: its layer is masked to the
    /// bubble shape, and a mask clips a shadow as readily as it clips a sublayer.
    static func raise(_ view: UIView, shape: UIBezierPath?) {
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = shape == nil ? 0 : liftShadowOpacity
        view.layer.shadowRadius = liftShadowRadius
        view.layer.shadowOffset = liftShadowOffset
        view.layer.shadowPath = shape?.cgPath
    }

    /// Returns `view` to the transcript's plane. Must run for every `raise`, including on the way out
    /// of a menu that was dismissed rather than acted on — the lifted bubble is a live cell subview,
    /// and a recycled cell that kept the shadow would cast it in the transcript.
    static func lower(_ view: UIView) {
        view.layer.shadowOpacity = 0
        view.layer.shadowPath = nil
    }

    /// White-opacity wash for a sender, composited over the conversation background by `apply`.
    static func fill(isFromSelf: Bool) -> UIColor {
        isFromSelf
            ? UIColor.white.withAlphaComponent(0.08)
            : UIColor.white.withAlphaComponent(0.02)
    }

    /// Per-corner radii: a bubble run flattens the inner corners (nearest the avatar column)
    /// from `baseRadius` to `groupedRadius` so stacked bubbles read as one column.
    static func radii(isFromSelf: Bool, groupedAbove: Bool, groupedBelow: Bool) -> RectangleCornerRadii {
        let top = groupedAbove ? groupedRadius : baseRadius
        let bottom = groupedBelow ? groupedRadius : baseRadius
        if isFromSelf {
            return RectangleCornerRadii(topLeading: baseRadius, bottomLeading: baseRadius, bottomTrailing: bottom, topTrailing: top)
        } else {
            return RectangleCornerRadii(topLeading: top, bottomLeading: bottom, bottomTrailing: baseRadius, topTrailing: baseRadius)
        }
    }
}
#endif
