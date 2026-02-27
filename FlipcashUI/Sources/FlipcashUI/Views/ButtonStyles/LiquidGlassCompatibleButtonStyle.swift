//
//  LiquidGlassCompatibleButtonStyle.swift
//  FlipcashUI
//
//  Created by Raul Riera on 2026-02-24.
//

import SwiftUI

/// A button style that applies a Liquid Glass effect on iOS 26+ and falls
/// back to a material background on earlier versions.
///
/// Use the convenience accessors for the desired shape:
/// ```swift
/// .buttonStyle(.liquidGlassCompatible)        // capsule (default)
/// .buttonStyle(.liquidGlassCompatibleCircle)   // circle
/// ```
public struct LiquidGlassCompatibleButtonStyle: ButtonStyle {

    public enum Shape {
        case capsule
        case circle
    }

    private let shape: Shape

    public init(shape: Shape = .capsule) {
        self.shape = shape
    }

    public func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26, *) {
            switch shape {
            case .capsule:
                configuration.label
                    .foregroundStyle(.white)
                    .glassEffect(.regular.interactive(), in: .capsule)
            case .circle:
                configuration.label
                    .foregroundStyle(.white)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
        } else {
            switch shape {
            case .capsule:
                configuration.label
                    .foregroundStyle(.white)
                    .background(.ultraThinMaterial, in: Capsule())
            case .circle:
                configuration.label
                    .foregroundColor(Color.textMain)
                    .background(
                        Circle()
                            .fill(Color.textMain.opacity(0.07))
                            .background(
                                Circle()
                                    .strokeBorder(Color.textMain.opacity(0.1), lineWidth: 1)
                            )
                    )
            }
        }
    }
}

extension ButtonStyle where Self == LiquidGlassCompatibleButtonStyle {
    public static var liquidGlassCompatible: LiquidGlassCompatibleButtonStyle { .init() }
    public static var liquidGlassCompatibleCircle: LiquidGlassCompatibleButtonStyle { .init(shape: .circle) }
}
