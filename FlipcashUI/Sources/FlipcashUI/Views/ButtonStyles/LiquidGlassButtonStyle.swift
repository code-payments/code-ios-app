//
//  LiquidGlassButtonStyle.swift
//  FlipcashUI
//
//  Created by Raul Riera on 2026-02-24.
//

import SwiftUI

/// A button style that applies a native Liquid Glass effect on iOS 26+ and
/// falls back to an ultra-thin material capsule on earlier versions.
///
/// ```swift
/// Button("Send as a Link") {
///     send()
/// }
/// .buttonStyle(.liquidGlass)
/// ```
public struct LiquidGlassButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26, *) {
            configuration.label
                .foregroundStyle(.white)
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            configuration.label
                .foregroundStyle(.white)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

extension ButtonStyle where Self == LiquidGlassButtonStyle {
    /// A button style that applies a native Liquid Glass effect on iOS 26+ and
    /// falls back to an ultra-thin material capsule on earlier versions.
    public static var liquidGlass: LiquidGlassButtonStyle { .init() }
}
