//
//  TextLinkButtonStyle.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI

/// A full-width text button with no fill, 44 pt high, for a help or escape link under the screen's
/// actions, like "Can't Find Your Access Key?" or a sheet's Cancel.
///
/// ```swift
/// Button("Cancel") {
///     dismiss()
/// }
/// .buttonStyle(.textLink)
/// ```
public struct TextLinkButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    /// Creates the text-link style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.appTextMedium)
            .foregroundStyle(Color.textMain.opacity(isEnabled ? 0.6 : 0.3))
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.buttonHeightThin)
            .contentShape(.rect)
            .buttonPress(isPressed: configuration.isPressed)
    }
}

extension ButtonStyle where Self == TextLinkButtonStyle {
    /// A full-width text button with no fill, for a help or escape link.
    public static var textLink: TextLinkButtonStyle {
        .init()
    }
}

// MARK: - Previews -

#Preview {
    Background(color: .backgroundMain) {
        VStack(spacing: Metrics.buttonGap) {
            Button("Log In") {}
                .buttonStyle(.filled)
            Button("Can't Find Your Access Key?") {}
                .buttonStyle(.textLink)
            Button("Can't Find Your Access Key?") {}
                .buttonStyle(.textLink)
                .disabled(true)
        }
        .padding(20)
    }
}
