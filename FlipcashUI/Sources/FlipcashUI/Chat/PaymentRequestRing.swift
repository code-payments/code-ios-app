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
    let diameter: CGFloat

    public init(fraction: Double, diameter: CGFloat = 26) {
        self.fraction = fraction
        self.diameter = diameter
    }

    private static let lineWidth: CGFloat = 2

    /// The disc sits 4 pt inside a 26 pt ring, scaled with the diameter.
    private var discDiameter: CGFloat { diameter - 2 * diameter * (4 / 26) }

    public var body: some View {
        ZStack {
            Circle()
                .inset(by: Self.lineWidth / 2)
                .stroke(Color.rowSeparator, lineWidth: Self.lineWidth)
            Circle()
                .inset(by: Self.lineWidth / 2)
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(Color.success, lineWidth: Self.lineWidth)
                .rotationEffect(.degrees(-90))
            Circle()
                .fill(Color.success)
                .frame(width: discDiameter, height: discDiameter)
            Text(verbatim: "$")
                .font(diameter > 30 ? .appTextMedium : .appTextCaption)
                .foregroundStyle(Color.black)
        }
        .frame(width: diameter, height: diameter)
        .requestMotion(value: fraction)
        .accessibilityHidden(true)
    }
}

private struct RequestMotion<Value: Equatable>: ViewModifier {

    let animation: Animation
    let value: Value

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

public extension View {

    /// Animates a change to `value` on a payment request already on screen: ring sweeps, a share
    /// turning paid, the ended look in the timeline. `animation(_:value:)` skips the first appearance, so
    /// nothing plays on load. With Reduce Motion on, the change is applied at once.
    func requestMotion<Value: Equatable>(_ animation: Animation = .easeOut(duration: 0.3), value: Value) -> some View {
        modifier(RequestMotion(animation: animation, value: value))
    }
}
