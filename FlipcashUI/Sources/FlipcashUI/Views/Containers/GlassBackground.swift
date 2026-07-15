//
//  GlassBackground.swift
//  FlipcashUI
//

import SwiftUI

extension View {
    /// Applies the app's standard glass surface: Liquid Glass on iOS 26,
    /// an ultra-thin material below.
    @ViewBuilder
    public func glassBackground(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
        }
    }
}
