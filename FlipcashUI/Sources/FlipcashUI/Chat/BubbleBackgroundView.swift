//
//  BubbleBackgroundView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI
import FlipcashCore

/// The shared chrome behind every chat bubble and cash card: a white-opacity fill with a hairline
/// border and a continuous, per-corner rounded shape. A same-sender run flattens the inner corners
/// from 12 to 6, which UIKit's `cornerCurve`/`maskedCorners` can't express, so the path is taken
/// straight from SwiftUI's `UnevenRoundedRectangle(.continuous)` (pure geometry, no hosted SwiftUI
/// views) and drawn into a `CAShapeLayer`.
final class BubbleBackgroundView: UIView {

    /// Base corner radius; the inner corner of a grouped run uses `groupedRadius`.
    static let baseRadius: CGFloat = 12
    static let groupedRadius: CGFloat = 6

    private let shapeMask = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private var radii = RectangleCornerRadii(topLeading: baseRadius, bottomLeading: baseRadius, bottomTrailing: baseRadius, topTrailing: baseRadius)

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

    /// Applies the sender fill and grouping radii for `message`.
    func apply(for message: ChatMessage, animated: Bool = false) {
        apply(
            fill: Self.fill(isFromSelf: message.sender == .me),
            radii: Self.radii(
                isFromSelf: message.sender == .me,
                groupedAbove: message.isContinuationFromPrevious,
                groupedBelow: message.isContinuedByNext
            ),
            animated: animated
        )
    }

    /// Applies the fill and radii, morphing the shape on the corner spring when `animated` is true.
    func apply(fill: UIColor, radii: RectangleCornerRadii, animated: Bool = false) {
        backgroundColor = fill
        let previous = self.radii
        self.radii = radii
        // A recycled cell applies directly (not animated) and can land mid-morph; drop the
        // in-flight animation so the new row renders its own shape instead of the old row's morph
        // playing over it. An in-place reconfigure keeps the same row's running morph.
        if !animated {
            shapeMask.removeAnimation(forKey: "cornerMorph")
            borderLayer.removeAnimation(forKey: "cornerMorph")
        }
        guard animated, !ChatMotion.isReduced, radii != previous, !bounds.isEmpty else {
            setNeedsLayout()
            return
        }
        let path = shapePath
        for layer in [shapeMask, borderLayer] {
            let morph = CASpringAnimation(perceptualDuration: ChatMotion.cornerMorph.duration, bounce: ChatMotion.cornerMorph.bounce)
            morph.keyPath = "path"
            // Retarget from wherever a still-running morph currently is, not its final value.
            morph.fromValue = layer.presentation()?.path ?? layer.path
            morph.toValue = path
            layer.add(morph, forKey: "cornerMorph")
            layer.path = path
        }
    }

    /// The bubble's continuous, per-corner rounded shape in its own coordinate space — the same
    /// geometry used for the layer mask. Clips the context-menu lift preview to the bubble.
    var maskingPath: UIBezierPath {
        UIBezierPath(cgPath: shapePath)
    }

    /// The current radii rendered into this view's bounds — the one geometry every consumer
    /// (mask, border, morph target, lift-preview clip) draws.
    private var shapePath: CGPath {
        UnevenRoundedRectangle(cornerRadii: radii, style: .continuous).path(in: bounds).cgPath
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let path = shapePath
        shapeMask.path = path
        borderLayer.path = path
        borderLayer.frame = bounds
    }

    /// White-opacity fill for a sender. Designed for the app's dark conversation background.
    static func fill(isFromSelf: Bool) -> UIColor {
        isFromSelf
            ? UIColor.white.withAlphaComponent(0.08)
            : UIColor.white.withAlphaComponent(0.02)
    }

    /// Per-corner radii: a same-sender run flattens the inner corners (nearest the avatar column)
    /// from 12 to 6 so stacked bubbles read as one column.
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
