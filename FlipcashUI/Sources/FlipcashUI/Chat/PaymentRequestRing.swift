//
//  PaymentRequestRing.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI

/// A green "$" disc inside a 2 pt ring, filled clockwise from 12 o'clock with a request's paid fraction.
public struct PaymentRequestRing: View {

    let fraction: Double
    let isEnded: Bool
    let isClosed: Bool
    let diameter: CGFloat

    /// `isClosed` draws "✓" in place of "$", for a request its creator closed.
    public init(fraction: Double, isEnded: Bool, isClosed: Bool = false, diameter: CGFloat = 26) {
        self.fraction = fraction
        self.isEnded = isEnded
        self.isClosed = isClosed
        self.diameter = diameter
    }

    private static let lineWidth: CGFloat = 2

    /// The disc sits 4 pt inside a 26 pt ring, scaled with the diameter.
    private var discDiameter: CGFloat { diameter - 2 * diameter * (4 / 26) }

    /// The arc and the disc share one color, green while the request is open.
    private var accent: Color { isEnded ? Color.textSecondary : Color.success }

    public var body: some View {
        ZStack {
            Circle()
                .inset(by: Self.lineWidth / 2)
                .stroke(Color.rowSeparator, lineWidth: Self.lineWidth)
            Circle()
                .inset(by: Self.lineWidth / 2)
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(accent, lineWidth: Self.lineWidth)
                .rotationEffect(.degrees(-90))
            Circle()
                .fill(accent)
                .frame(width: discDiameter, height: discDiameter)
            Text(verbatim: isClosed ? "✓" : "$")
                .font(diameter > 30 ? .appTextMedium : .appTextCaption)
                .foregroundStyle(Color.black)
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeOut(duration: 0.3), value: fraction)
        .accessibilityHidden(true)
    }
}
