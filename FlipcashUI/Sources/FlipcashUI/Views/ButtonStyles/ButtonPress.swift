//
//  ButtonPress.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI

/// The house press feedback: a held button shrinks slightly, or dims instead under Reduce Motion.
public struct ButtonPress: ViewModifier {

    private let isPressed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates the press for a button that is held while `isPressed` is true.
    public init(isPressed: Bool) {
        self.isPressed = isPressed
    }

    public func body(content: Content) -> some View {
        content
            .scaleEffect(!reduceMotion && isPressed ? Metrics.buttonPressScale : 1)
            .opacity(reduceMotion && isPressed ? Metrics.buttonPressDim : 1)
            .animation(Metrics.buttonPressAnimation, value: isPressed)
    }
}

extension View {
    /// Draws the house press feedback while `isPressed` is true.
    public func buttonPress(isPressed: Bool) -> some View {
        modifier(ButtonPress(isPressed: isPressed))
    }
}

// MARK: - Previews -

#Preview {
    Background(color: .backgroundMain) {
        VStack(spacing: 20) {
            Button("Primary") {}
                .buttonStyle(.filled)
            Button("Secondary") {}
                .buttonStyle(.subtle)
            Button("Secondary") {}
                .buttonStyle(.subtle)
                .disabled(true)
            Button("Compact") {}
                .buttonStyle(.filledCompact)
        }
        .padding(20)
    }
}
