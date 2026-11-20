//
//  PressButtonStyle.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI

/// Adds the house press to a button whose label draws its own surface and dims that label while
/// the button is disabled. Sets no hit shape, so each call site sets its own.
public struct PressButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    /// The opacity a disabled button's label dims to, the dim `.plain` draws.
    private static let disabledOpacity: Double = 0.5

    /// Creates the press-only style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? 1 : Self.disabledOpacity)
            .buttonPress(isPressed: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressButtonStyle {
    /// The house press and a disabled dim, with no drawing of its own.
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
