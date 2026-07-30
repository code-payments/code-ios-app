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

    /// The glass surface as a background layer *behind* the content, rather than
    /// wrapping it. Use for a surface that hosts its own touch-tracking control
    /// (a text field): applying `glassEffect` to the control reparents its text
    /// view into the glass platter and breaks the selection grabbers. Keep this
    /// out of a `GlassEffectContainer` — the container composites its glass above
    /// sibling content, which would draw the glass over the text.
    @ViewBuilder
    public func glassFieldBackground(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26, *) {
            background {
                Color.clear.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
        }
    }
}
