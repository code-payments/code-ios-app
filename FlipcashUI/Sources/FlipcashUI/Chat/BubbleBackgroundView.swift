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

    func apply(fill: UIColor, radii: RectangleCornerRadii) {
        backgroundColor = fill
        self.radii = radii
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let path = UnevenRoundedRectangle(cornerRadii: radii, style: .continuous).path(in: bounds).cgPath
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
