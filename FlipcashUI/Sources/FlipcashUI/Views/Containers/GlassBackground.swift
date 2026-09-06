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

    /// The app's standard glass surface in a capsule: Liquid Glass on iOS 26, an
    /// ultra-thin material below.
    ///
    /// Wraps rather than backgrounds, which is safe for a capsule of static
    /// content. Don't reach for it around an editable text field — see
    /// ``glassFieldBackground(cornerRadius:)`` for why.
    @ViewBuilder
    public func glassCapsuleBackground() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular, in: .capsule)
        } else {
            background(.ultraThinMaterial, in: .capsule)
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
