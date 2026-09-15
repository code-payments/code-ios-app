//
//  PartialSheet.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct PartialSheet<T>: View where T: View {
    
    public let background: Color
    public let prefersGlass: Bool
    public let canDismiss: Bool
    public let canAccessBackground: Bool
    public let content: T
    
    @State private var displayHeight: CGFloat = UIScreen.main.bounds.height
    
    /// - Parameter prefersGlass: Draws the sheet on Liquid Glass where the OS has
    ///   it, and on `background` everywhere else. Opt-in: the glass takes its
    ///   colour from what's behind the sheet, so it only reads on a sheet short
    ///   enough to leave that visible.
    public init(background: Color = .backgroundSecondary, prefersGlass: Bool = false, canDismiss: Bool = true, canAccessBackground: Bool = false, @ViewBuilder content: () -> T) {
        self.background = background
        self.prefersGlass = prefersGlass
        self.canDismiss = canDismiss
        self.canAccessBackground = canAccessBackground
        self.content = content()
    }
    
    public var body: some View {
        // The glass is the presentation background, so the content can't lay its
        // own colour over it.
        Background(color: isGlass ? .clear : background) {
            content
                .frame(maxWidth: .infinity)
                .overlay {
                    GeometryReader { g in
                        Color.clear
                            .onAppear {
                                displayHeight = g.size.height
                            }
                            .onChange(of: g.size.height) { _, newHeight in
                                displayHeight = newHeight
                            }
                    }
                }
        }
        .presentationDetents([.height(displayHeight)])
        .presentationBackgroundInteraction(canAccessBackground ? .enabled : .disabled)
        .interactiveDismissDisabled(!canDismiss)
        .compatiblePresentationBackground(background, prefersGlass: prefersGlass)
    }

    private var isGlass: Bool {
        if #available(iOS 26, *) {
            return prefersGlass
        }
        return false
    }
}

/// Works around an iOS 18 issue where `.presentationBackground(.clear)` results
/// in a clear sheet background. Falls back to `.thinMaterial` for clear backgrounds.
///
/// On iOS 26+, `.clear` is natively styled by Liquid Glass, so this workaround
/// can be removed once iOS 18 support is dropped.
private struct SheetPresentationBackground: ViewModifier {
    var color: Color
    var prefersGlass: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26, *), prefersGlass {
            // Square corners: the sheet clips the background to its own shape, and
            // a radius here would inset the glass from that edge.
            content
                .presentationBackground {
                    Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 0))
                }
        } else if color == .clear {
            content
                .presentationBackground(.thinMaterial)
        } else {
            content
                .presentationBackground(color)
        }
    }
}

private extension View {
    func compatiblePresentationBackground(_ color: Color, prefersGlass: Bool) -> some View {
        modifier(SheetPresentationBackground(color: color, prefersGlass: prefersGlass))
    }
}
