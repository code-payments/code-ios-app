//
//  BleedRGB.swift
//  FlipcashUI
//

import SwiftUI

/// A gamma-encoded sRGB color (components 0…1), the currency of the bleed system.
nonisolated struct BleedRGB: Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    /// The color as a SwiftUI `Color` in sRGB.
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }

    /// WCAG relative luminance.
    var relativeLuminance: Double {
        0.2126 * Self.linear(red) + 0.7152 * Self.linear(green) + 0.0722 * Self.linear(blue)
    }

    /// WCAG contrast ratio against another color (1…21).
    func contrast(with other: BleedRGB) -> Double {
        let a = relativeLuminance + 0.05
        let b = other.relativeLuminance + 0.05
        return max(a, b) / min(a, b)
    }

    /// Source-over blend of `top` at `opacity` onto `self`, in gamma space like UIKit compositing.
    func blended(with top: BleedRGB, opacity: Double) -> BleedRGB {
        BleedRGB(
            red: red + (top.red - red) * opacity,
            green: green + (top.green - green) * opacity,
            blue: blue + (top.blue - blue) * opacity
        )
    }

    /// `top` at `opacity` drawn onto `self` with `.plusLighter` (per channel `D + a·S`, clamped), in
    /// gamma space like Core Animation; any other mode is a source-over blend.
    func blended(with top: BleedRGB, opacity: Double, mode: BlendMode) -> BleedRGB {
        switch mode {
        case .plusLighter:
            BleedRGB(
                red: min(1, red + top.red * opacity),
                green: min(1, green + top.green * opacity),
                blue: min(1, blue + top.blue * opacity)
            )
        default:
            blended(with: top, opacity: opacity)
        }
    }

    static let white = BleedRGB(red: 1, green: 1, blue: 1)

    // MARK: Transfer functions

    /// The linear-light value of a gamma-encoded component.
    static func linear(_ encoded: Double) -> Double {
        encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)
    }

    /// The gamma-encoded value of a linear-light component.
    static func encoded(_ linear: Double) -> Double {
        linear <= 0.0031308 ? linear * 12.92 : 1.055 * pow(linear, 1 / 2.4) - 0.055
    }
}
