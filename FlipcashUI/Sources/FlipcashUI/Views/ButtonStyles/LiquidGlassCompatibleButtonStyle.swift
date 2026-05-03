//
//  LiquidGlassCompatibleButtonStyle.swift
//  FlipcashUI
//
//  Created by Raul Riera on 2026-02-24.
//

import SwiftUI

public enum LiquidGlassButtonShape {
    case capsule
    case circle
}

extension View {
    /// Applies Apple's native `.buttonStyle(.glass)` on iOS 26+ and falls back
    /// to a material/border style on earlier versions.
    ///
    /// `.buttonStyle(.glass)` is the Apple-recommended path for glass buttons
    /// (WWDC25 session 323). Applying `.glassEffect(.interactive())` inside a
    /// custom `ButtonStyle` stacks two gesture layers on the same view: the
    /// glass press animation can claim a tap that arrives mid-feedback,
    /// swallowing the `Button` action when the user taps rapidly.
    ///
    /// Use the convenience accessors:
    /// ```swift
    /// .liquidGlassButtonStyle()                 // capsule (default)
    /// .liquidGlassButtonStyle(shape: .circle)   // circular icon
    /// ```
    @ViewBuilder
    public func liquidGlassButtonStyle(shape: LiquidGlassButtonShape = .capsule) -> some View {
        if #available(iOS 26, *) {
            switch shape {
            case .capsule:
                self
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
            case .circle:
                self
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
            }
        } else {
            self.buttonStyle(LiquidGlassCompatibleButtonStyle(shape: shape))
        }
    }
}

struct LiquidGlassCompatibleButtonStyle: ButtonStyle {

    let shape: LiquidGlassButtonShape

    func makeBody(configuration: Configuration) -> some View {
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
