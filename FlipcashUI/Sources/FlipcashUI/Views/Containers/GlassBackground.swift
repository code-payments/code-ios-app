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

    /// The app's glass surface carrying a colour: Liquid Glass takes the tint natively on iOS 26,
    /// and below it the colour is laid over an ultra-thin material.
    ///
    /// For a surface whose colour is the point. Non-interactive — a tinted rule or badge, not a
    /// control, so it has no touch response to track.
    @ViewBuilder
    public func glassBackground(cornerRadius: CGFloat, tint: Color) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
        } else {
            // Short of opaque, so the material still reads as a material, but saturated enough that
            // a few points of it still carry a recognisable colour.
            background(tint.opacity(0.6), in: .rect(cornerRadius: cornerRadius))
                .background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
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
