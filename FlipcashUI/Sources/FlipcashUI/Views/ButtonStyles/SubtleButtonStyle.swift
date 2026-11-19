//
//  SubtleButtonStyle.swift
//  FlipcashUI
//
//  Created by Raul Riera.
//  Copyright © 2025 Code Inc. All rights reserved.
//

import SwiftUI

/// A full-width capsule button style on a translucent white fill, used for
/// secondary actions like "Not Now" or "Cancel".
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
            .foregroundStyle(isEnabled ? Color.textMain : Color.textMain.opacity(0.2))
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.buttonHeight)
            .background(Color.actionSecondary, in: Capsule())
            .contentShape(Capsule())
            .buttonPress(isPressed: configuration.isPressed)
    }
}

extension ButtonStyle where Self == SubtleButtonStyle {
    /// A full-width translucent capsule button for secondary actions.
    public static var subtle: SubtleButtonStyle {
        .init()
    }
}
