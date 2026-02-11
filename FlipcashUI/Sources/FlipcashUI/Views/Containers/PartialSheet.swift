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
    public let canDismiss: Bool
    public let canAccessBackground: Bool
    public let content: T
    
    @State private var displayHeight: CGFloat = UIScreen.main.bounds.height
    
    public init(background: Color = .backgroundSecondary, canDismiss: Bool = true, canAccessBackground: Bool = false, @ViewBuilder content: () -> T) {
        self.background = background
        self.canDismiss = canDismiss
        self.canAccessBackground = canAccessBackground
        self.content = content()
    }
    
    public var body: some View {
        Background(color: background) {
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
        .compatiblePresentationBackground(background)
    }
}

/// Works around an iOS 18 issue where `.presentationBackground(.clear)` results
/// in a clear sheet background. Falls back to `.thinMaterial` for clear backgrounds.
///
/// On iOS 26+, `.clear` is natively styled by Liquid Glass, so this workaround
/// can be removed once iOS 18 support is dropped.
private struct SheetPresentationBackground: ViewModifier {
    var color: Color

    func body(content: Content) -> some View {
        if color == .clear {
            content
                .presentationBackground(.thinMaterial)
        } else {
            content
                .presentationBackground(color)
        }
    }
}

private extension View {
    func compatiblePresentationBackground(_ color: Color) -> some View {
        modifier(SheetPresentationBackground(color: color))
    }
}
