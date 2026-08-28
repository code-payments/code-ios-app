//
//  BubbleBackgroundView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI

/// The shared chrome behind every chat bubble and cash card: a white-opacity fill with a hairline
/// border and a continuous, per-corner rounded shape. A same-sender run flattens the inner corners
/// from 12 to 4, which UIKit's `cornerCurve`/`maskedCorners` can't express, so the path is taken
/// straight from SwiftUI's `UnevenRoundedRectangle(.continuous)` (pure geometry, no hosted SwiftUI
/// views) and drawn into a `CAShapeLayer`.
final class BubbleBackgroundView: UIView {

    /// Base corner radius; the inner corner of a grouped run uses `groupedRadius`.
    static let baseRadius: CGFloat = 12
    static let groupedRadius: CGFloat = 4

    private let shapeMask = CAShapeLayer()
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
        backgroundColor = fill
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

    /// White-opacity fill for a sender. Designed for the app's dark conversation background.
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
