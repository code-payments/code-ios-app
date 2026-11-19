//
//  PressButtonStyle.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI

/// Adds the house press to a button whose label draws its own surface, and sets no hit shape, so
/// each call site sets its own.
public struct PressButtonStyle: ButtonStyle {

    /// Creates the press-only style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .buttonPress(isPressed: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressButtonStyle {
    /// The house press with no drawing of its own.
    public static var pressable: PressButtonStyle {
        .init()
    }
}

// MARK: - Previews -

#Preview {
    Background(color: .backgroundMain) {
        Button {} label: {
            Text("Undo")
                .font(.appTextSmall)
                .foregroundStyle(Color.textAction)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.action, in: Capsule())
                .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .padding(20)
    }
}
