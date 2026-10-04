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

    /// Dark-tinted glass for a control floating over a photo or viewfinder, where clear glass takes
    /// on the image behind it and washes the glyph out.
    @ViewBuilder
    public func overlayGlassBackground(in shape: some Shape) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.tint(.black.opacity(0.45)).interactive(), in: shape)
        } else {
            background(Color.black.opacity(0.45), in: shape)
                .background(.ultraThinMaterial, in: shape)
        }
    }

    /// The app's glass surface for a panel that holds its own buttons: Liquid Glass on iOS 26, an
    /// ultra-thin material below. Non-interactive, because `.interactive()` on the container competes
    /// with its buttons for the tap.
    @ViewBuilder
    public func panelGlassBackground(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
        }
    }

    /// The app's glass surface clipped to a capsule, for a control whose shape is
    /// fully rounded — the floating tab bar and the Scan tab's gallery button.
    @ViewBuilder
    public func capsuleGlassBackground() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.interactive(), in: Capsule())
        } else {
            background(.ultraThinMaterial, in: Capsule())
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

    /// The chat composer's glass in `shape`, as a layer of its own: Liquid Glass with a light white
    /// tint, joined by `id` to the other composer glass in an enclosing container. A tinted material
    /// before iOS 26.
    @ViewBuilder
    public func composerGlass(in shape: some Shape, id: String, namespace: Namespace.ID) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.tint(Color.white.opacity(0.03)).interactive(), in: shape)
                .glassEffectID(id, in: namespace)
        } else {
            background(Color.white.opacity(0.03), in: shape)
                .background(.ultraThinMaterial, in: shape)
        }
    }

    /// The chat composer's light rim around `shape`, brightest along the top.
    public func composerRim(in shape: some InsettableShape) -> some View {
        overlay {
            shape
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.white.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        }
    }
}
