//
//  BubbleBackgroundView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit

/// The shared chrome behind every chat bubble and cash card: a white-opacity fill with a hairline
/// border and independent per-corner radii. A same-sender run flattens the inner corners from 12
/// to 6, which `cornerRadius`/`maskedCorners` can't express (they force one radius), so the shape
/// is drawn as a `UIBezierPath` mask plus a stroked border layer.
final class BubbleBackgroundView: UIView {

    /// Base corner radius; the inner corner of a grouped run uses `groupedRadius`.
    static let baseRadius: CGFloat = 12
    static let groupedRadius: CGFloat = 6

    private let shapeMask = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private var corners = Corners(topLeft: baseRadius, topRight: baseRadius, bottomLeft: baseRadius, bottomRight: baseRadius)

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.mask = shapeMask
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.strokeColor = UIColor.white.withAlphaComponent(0.03).cgColor // stroke
        borderLayer.lineWidth = 1
        layer.addSublayer(borderLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(fill: UIColor, corners: Corners) {
        backgroundColor = fill
        self.corners = corners
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let path = Self.path(in: bounds, corners: corners)
        shapeMask.path = path
        borderLayer.path = path
        borderLayer.frame = bounds
    }

    /// White-opacity fill for a sender. Designed for the app's dark conversation background.
    static func fill(isFromSelf: Bool) -> UIColor {
        isFromSelf
            ? UIColor.white.withAlphaComponent(0.08)  // sentFill
            : UIColor.white.withAlphaComponent(0.02)  // receivedFill
    }

    /// The four corner radii for a bubble. A same-sender run flattens the inner corners (the ones
    /// nearest the avatar column) from 12 to 6 so stacked bubbles read as one column.
    struct Corners: Equatable {
        var topLeft: CGFloat
        var topRight: CGFloat
        var bottomLeft: CGFloat
        var bottomRight: CGFloat
    }

    /// Pure mapping of sender + grouping to the four radii, mirroring the SwiftUI bubble.
    static func corners(isFromSelf: Bool, groupedAbove: Bool, groupedBelow: Bool) -> Corners {
        let top = groupedAbove ? groupedRadius : baseRadius
        let bottom = groupedBelow ? groupedRadius : baseRadius
        // Self bubbles hug the trailing edge, so their inner (right) corners flatten; received
        // bubbles hug the leading edge, so their inner (left) corners flatten.
        if isFromSelf {
            return Corners(topLeft: baseRadius, topRight: top, bottomLeft: baseRadius, bottomRight: bottom)
        } else {
            return Corners(topLeft: top, topRight: baseRadius, bottomLeft: bottom, bottomRight: baseRadius)
        }
    }

    /// A rounded-rect path with independent per-corner radii.
    static func path(in rect: CGRect, corners c: Corners) -> CGPath {
        let path = UIBezierPath()
        let (minX, minY, maxX, maxY) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
        path.move(to: CGPoint(x: minX + c.topLeft, y: minY))
        path.addLine(to: CGPoint(x: maxX - c.topRight, y: minY))
        path.addArc(withCenter: CGPoint(x: maxX - c.topRight, y: minY + c.topRight), radius: c.topRight, startAngle: -.pi / 2, endAngle: 0, clockwise: true)
        path.addLine(to: CGPoint(x: maxX, y: maxY - c.bottomRight))
        path.addArc(withCenter: CGPoint(x: maxX - c.bottomRight, y: maxY - c.bottomRight), radius: c.bottomRight, startAngle: 0, endAngle: .pi / 2, clockwise: true)
        path.addLine(to: CGPoint(x: minX + c.bottomLeft, y: maxY))
        path.addArc(withCenter: CGPoint(x: minX + c.bottomLeft, y: maxY - c.bottomLeft), radius: c.bottomLeft, startAngle: .pi / 2, endAngle: .pi, clockwise: true)
        path.addLine(to: CGPoint(x: minX, y: minY + c.topLeft))
        path.addArc(withCenter: CGPoint(x: minX + c.topLeft, y: minY + c.topLeft), radius: c.topLeft, startAngle: .pi, endAngle: .pi * 1.5, clockwise: true)
        path.close()
        return path.cgPath
    }
}
#endif
