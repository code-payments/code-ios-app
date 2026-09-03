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
/// A same-sender run flattens the inner corners
/// from 12 to 4, which UIKit's `cornerCurve`/`maskedCorners` can't express, so the path is taken
/// straight from SwiftUI's `UnevenRoundedRectangle(.continuous)` (pure geometry, no hosted SwiftUI
/// views) and drawn into a `CAShapeLayer`.
final class BubbleBackgroundView: UIView {

    /// Base corner radius; the inner corner of a grouped run uses `groupedRadius`.
    static let baseRadius: CGFloat = 12
    static let groupedRadius: CGFloat = 4

    private let shapeMask = CAShapeLayer()
    private let washLayer = CALayer()
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
        washLayer.actions = ["position": NSNull(), "bounds": NSNull()]
        layer.addSublayer(washLayer)
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.strokeColor = UIColor.white.withAlphaComponent(0.03).cgColor
        borderLayer.lineWidth = 1
        layer.addSublayer(borderLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Sets the chrome. `identity` is the row this is drawing — pass it, and a later `apply` for the
    /// same row that changes the radii morphs the corner instead of snapping it. A first setup, a
    /// recycled view taking a new row, and any caller that passes no identity all snap, which is what
    /// keeps a reused cell from animating in someone else's shape.
    func apply(fill: UIColor, radii: RectangleCornerRadii, identity: String? = nil) {
        washLayer.backgroundColor = fill.cgColor
        pendingCornerMorph = identity != nil && identity == self.identity && radii != self.radii
        self.identity = identity
        self.radii = radii
        setNeedsLayout()
    }

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
    /// flattened grouped corner instead of falling back to the view's square bounds.
    ///
    /// Applied to the view *hosting* the chrome, never to this view: its layer is masked to the
    /// bubble shape, and a mask clips a shadow as readily as it clips a sublayer.
    static func raise(_ view: UIView, shape: UIBezierPath?) {
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = liftShadowOpacity
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

    /// Per-corner radii: a same-sender run flattens the inner corners (nearest the avatar column)
    /// from 12 to 4 so stacked bubbles read as one column.
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
