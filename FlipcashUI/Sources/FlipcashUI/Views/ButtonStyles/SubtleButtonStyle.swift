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

    private let isCompact: Bool
    private var backing: AnyShapeStyle?

    /// Internal only. Use the static accessors (`.subtle`, `.subtleCompact`) instead.
    init(isCompact: Bool) {
        self.isCompact = isCompact
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.appTextMedium)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, Metrics.buttonPadding)
            .foregroundStyle(isEnabled ? Color.textMain : Color.textMain.opacity(0.2))
            .frame(maxWidth: .infinity)
            .frame(height: isCompact ? Metrics.buttonHeightThin : Metrics.buttonHeight)
            .background {
                ZStack {
                    if let backing {
                        Capsule().fill(backing)
                    }
                    Capsule()
                        .fill(Color.actionSecondary)
                }
            }
            .contentShape(Capsule())
            .buttonPress(isPressed: configuration.isPressed)
    }

    /// Returns this style drawn over `backing`, which keeps content scrolling under the translucent
    /// fill from showing through it and shrinks with the press.
    public func backed(by backing: some ShapeStyle) -> SubtleButtonStyle {
        var style = self
        style.backing = AnyShapeStyle(backing)
        return style
    }
}

extension ButtonStyle where Self == SubtleButtonStyle {
    /// A full-width translucent capsule button for secondary actions.
    public static var subtle: SubtleButtonStyle {
        .init(isCompact: false)
    }

    /// A full-width translucent capsule button for secondary actions (compact variant).
    public static var subtleCompact: SubtleButtonStyle {
        .init(isCompact: true)
    }
}
