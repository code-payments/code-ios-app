//
//  TrayCloseButton.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI

/// Central Icons' CrossMedium: two strokes across a 24-unit box, inset 6.5 on every side.
///
/// The geometry is redrawn here rather than shipping the licensed SVG; stroke it with round caps.
nonisolated struct CrossMediumShape: Shape {

    /// The box the icon is drawn in, and how far its strokes sit inside it.
    private static let box: CGFloat = 24
    private static let inset: CGFloat = 6.5

    /// The share of the box the strokes span, for sizing the box from a wanted cross size.
    static var extentRatio: CGFloat { (box - 2 * inset) / box }

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / Self.box
        let low = Self.inset * scale
        let high = (Self.box - Self.inset) * scale
        let origin = CGPoint(x: rect.midX - Self.box * scale / 2, y: rect.midY - Self.box * scale / 2)
        var path = Path()
        path.move(to: CGPoint(x: origin.x + low, y: origin.y + low))
        path.addLine(to: CGPoint(x: origin.x + high, y: origin.y + high))
        path.move(to: CGPoint(x: origin.x + high, y: origin.y + low))
        path.addLine(to: CGPoint(x: origin.x + low, y: origin.y + high))
        return path
    }
}

/// The tray's X: the cross on a circle, with a 44 pt tap target. It goes back a step from the
/// second step on and dismisses on the root.
struct TrayCloseButton: View {

    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        let size = TrayMetrics.closeSize
        let crossBox = TrayMetrics.closeGlyphSize / CrossMediumShape.extentRatio
        Button(action: action) {
            CrossMediumShape()
                .stroke(Color.textMain, style: StrokeStyle(lineWidth: TrayMetrics.closeStroke, lineCap: .round))
                .opacity(TrayMetrics.closeGlyphOpacity)
                .frame(width: crossBox, height: crossBox)
                .frame(width: size, height: size)
                // A white wash; there is no token for it yet.
                .background(Color.white.opacity(TrayMetrics.closeFillOpacity), in: Circle())
                .frame(width: TrayMetrics.closeHitSize, height: TrayMetrics.closeHitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(TrayDimPressStyle())
        // Lays out at the circle's size so the circle sits on the tray's padding; the tap target
        // overhangs it.
        .padding(-(TrayMetrics.closeHitSize - size) / 2)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Dims a tray control while pressed, as the house's icon and card buttons do.
struct TrayDimPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview("TrayCloseButton") {
    TrayCloseButton(accessibilityLabel: "Close") {}
        .padding(40)
        .background(Color.backgroundSecondary)
}
