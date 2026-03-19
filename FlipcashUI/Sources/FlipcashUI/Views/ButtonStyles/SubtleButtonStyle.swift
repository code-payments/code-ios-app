//
//  SubtleButtonStyle.swift
//  FlipcashUI
//
//  Created by Raul Riera.
//  Copyright © 2025 Code Inc. All rights reserved.
//

import SwiftUI

/// A full-width button style with no background, used for secondary actions
/// like "Not Now" or "Cancel".
///
/// ```swift
/// Button("Not Now") {
///     dismiss()
/// }
/// .buttonStyle(.subtle)
/// ```
public struct SubtleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.appTextMedium)
            .foregroundStyle(Color.textMain.opacity(isEnabled ? 0.6 : 0.3))
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.buttonHeight)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == SubtleButtonStyle {
    /// A full-width text-only button for secondary actions.
    public static var subtle: SubtleButtonStyle {
        .init()
    }
}
