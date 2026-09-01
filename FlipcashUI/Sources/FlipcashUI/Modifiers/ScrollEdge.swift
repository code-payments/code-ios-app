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
