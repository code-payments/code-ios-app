//
//  FilledButtonStyle.swift
//  FlipcashUI
//
//  Created by Raul Riera.
//  Copyright © 2025 Code Inc. All rights reserved.
//

import SwiftUI

/// A full-width button style with a rounded filled background that adjusts
/// its text and background colors for the disabled state automatically.
///
/// Several opacity presets are available through the static accessors:
///
/// ```swift
/// Button("Buy") {
///     executeTrade()
/// }
/// .buttonStyle(.filled)
/// ```
///
/// Use the lower-opacity variants (`.filled50`, `.filled20`, `.filled10`)
/// for secondary or de-emphasised actions.
public struct FilledButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    private let textColor: Color
    private let textDisabledColor: Color
    private let overlayColor: Color
    private let overlayDisabledColor: Color

    /// Internal only. Use the static accessors (e.g., `.filled`, `.filled50`) instead.
    init(
        textColor: Color,
        textDisabledColor: Color,
        overlayColor: Color,
        overlayDisabledColor: Color
    ) {
        self.textColor = textColor
        self.textDisabledColor = textDisabledColor
        self.overlayColor = overlayColor
        self.overlayDisabledColor = overlayDisabledColor
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.appTextMedium)
            .foregroundStyle(isEnabled ? textColor : textDisabledColor)
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.buttonHeight)
            .background {
                RoundedRectangle(cornerRadius: Metrics.buttonRadius)
                    .fill(isEnabled ? overlayColor : overlayDisabledColor)
            }
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == FilledButtonStyle {
    /// A full-width filled button with the primary action color.
    public static var filled: FilledButtonStyle {
        .init(
            textColor: .textAction,
            textDisabledColor: .textMain.opacity(0.2),
            overlayColor: .action,
            overlayDisabledColor: .action.opacity(0.1)
        )
    }
    /// A full-width filled button at 50% action color opacity.
    public static var filled50: FilledButtonStyle {
        .init(
            textColor: .textMain,
            textDisabledColor: .textMain.opacity(0.2),
            overlayColor: .action.opacity(0.5),
            overlayDisabledColor: .action.opacity(0.5)
        )
    }
    /// A full-width filled button at 20% action color opacity.
    public static var filled20: FilledButtonStyle {
        .init(
            textColor: .textMain,
            textDisabledColor: .textMain.opacity(0.2),
            overlayColor: .action.opacity(0.2),
            overlayDisabledColor: .action.opacity(0.2)
        )
    }
    /// A full-width filled button at 10% action color opacity.
    public static var filled10: FilledButtonStyle {
        .init(
            textColor: .textMain,
            textDisabledColor: .textMain.opacity(0.2),
            overlayColor: .action.opacity(0.1),
            overlayDisabledColor: .action.opacity(0.1)
        )
    }
}
