//
//  PaymentRequestRing.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI

/// A ring around a green "$" disc, filled clockwise from 12 o'clock with a request's paid fraction.
public struct PaymentRequestRing: View {

    let fraction: Double
    let isEnded: Bool
    let diameter: CGFloat

    public init(fraction: Double, isEnded: Bool, diameter: CGFloat = 26) {
        self.fraction = fraction
        self.isEnded = isEnded
        self.diameter = diameter
    }

    private var lineWidth: CGFloat { diameter * 0.12 }

    /// The arc and the disc behind the "$" share one color, green while the request is open.
    private var accent: Color { isEnded ? Color.textSecondary : Color.success }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(Color.textMain.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle()
                .fill(accent)
                .frame(width: diameter * 0.7, height: diameter * 0.7)
            Text(verbatim: "$")
                .font(.appTextCaption)
                .foregroundStyle(Color.black)
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeOut(duration: 0.3), value: fraction)
        .accessibilityHidden(true)
    }
}
