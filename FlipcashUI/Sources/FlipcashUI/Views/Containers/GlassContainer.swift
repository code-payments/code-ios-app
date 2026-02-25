//
//  GlassContainer.swift
//  FlipcashUI
//
//  Created by Raul Riera on 2026-02-24.
//

import SwiftUI

/// A backward-compatible wrapper around `GlassEffectContainer`.
///
/// On iOS 26+ this uses the native `GlassEffectContainer` so grouped
/// glass elements share the same visual context. On earlier versions
/// the content is rendered as-is.
///
/// ```swift
/// GlassContainer(spacing: 30) {
///     HStack(spacing: 30) {
///         Button("Send") { }
///             .buttonStyle(.liquidGlass)
///         Button("Cancel") { }
///             .buttonStyle(.liquidGlass)
///     }
/// }
/// ```
public struct GlassContainer<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    public init(spacing: CGFloat = 0, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}
