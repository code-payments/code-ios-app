//
//  ScrollEdge.swift
//  FlipcashUI
//

import SwiftUI

extension View {

    /// Softens scroll edge effects on iOS 26+, so content fades out under a bar
    /// instead of meeting the system's default hard edge line.
    ///
    /// Applies to every scrollable view below it, so the app applies it once at
    /// the root (`FlipcashApp`) rather than per screen. No-op below iOS 26,
    /// where the effect doesn't exist. The effect is drawn by the bar's own
    /// background, so it renders only where a bar is visible — a screen that
    /// hides its navigation bar has to draw its own fade, and a UIKit scroll
    /// view has to set `topEdgeEffect`/`bottomEdgeEffect` itself.
    public func softScrollEdge(for edges: Edge.Set = .top) -> some View {
        modifier(SoftScrollEdge(edges: edges))
    }

    /// Hides the top scroll edge effect until the scroll view has moved past `offset`, for a screen
    /// whose content starts with a full-bleed image under the bar: at rest the effect would only
    /// darken that image and leave a visible band where it stops. No-op below iOS 26.
    public func hidesTopScrollEdge(untilOffset offset: CGFloat) -> some View {
        modifier(HidesTopScrollEdge(offset: offset))
    }

    /// Pins `bar` to `edge` so the scroll content below it runs underneath. On iOS 26+ the bar joins
    /// the scroll edge effect; before that it's a plain safe-area inset.
    @ViewBuilder
    public func scrollEdgeBar(_ edge: VerticalEdge, @ViewBuilder _ bar: () -> some View) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: edge, spacing: 0, content: bar)
        } else {
            safeAreaInset(edge: edge, spacing: 0, content: bar)
        }
    }
}

private struct SoftScrollEdge: ViewModifier {

    let edges: Edge.Set

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: edges)
        } else {
            content
        }
    }
}

private struct HidesTopScrollEdge: ViewModifier {

    let offset: CGFloat

    @State private var isPastOffset = false

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y > offset } action: { _, isPast in
                    isPastOffset = isPast
                }
                .scrollEdgeEffectHidden(!isPastOffset, for: .top)
        } else {
            content
        }
    }
}
