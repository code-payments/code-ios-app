//
//  FilledButtonStyle.swift
//  FlipcashUI
//
//  Created by Raul Riera.
//  Copyright © 2025 Code Inc. All rights reserved.
//

import SwiftUI

/// A full-width capsule button style with a filled background that adjusts
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
/// Use `.subtle` for the secondary action beside it.
public struct FilledButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    private let textColor: Color
    private let textDisabledColor: Color
    private let overlayColor: Color
    private let overlayDisabledColor: Color
    private let isCompact: Bool
    private var backing: AnyShapeStyle?

    /// Internal only. Use the static accessors (e.g., `.filled`, `.filledCompact`) instead.
    init(
        textColor: Color,
        textDisabledColor: Color,
        overlayColor: Color,
        overlayDisabledColor: Color,
        isCompact: Bool
    ) {
        self.textColor = textColor
        self.textDisabledColor = textDisabledColor
        self.overlayColor = overlayColor
        self.overlayDisabledColor = overlayDisabledColor
        self.isCompact = isCompact
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.appTextMedium)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, Metrics.buttonPadding)
            .foregroundStyle(isEnabled ? textColor : textDisabledColor)
            .frame(maxWidth: .infinity)
            .frame(height: isCompact ? Metrics.buttonHeightThin : Metrics.buttonHeight)
            .background {
                ZStack {
                    if let backing {
                        Capsule().fill(backing)
                    }
                    Capsule()
                        .fill(isEnabled ? overlayColor : overlayDisabledColor)
                }
            }
            .contentShape(Capsule())
            .buttonPress(isPressed: configuration.isPressed)
    }

    /// Returns this style drawn over `backing`, which keeps content scrolling under a translucent
    /// fill from showing through it and shrinks with the press.
    public func backed(by backing: some ShapeStyle) -> FilledButtonStyle {
        var style = self
        style.backing = AnyShapeStyle(backing)
        return style
    }
}

extension ButtonStyle where Self == FilledButtonStyle {
    /// A full-width filled button with the primary action color.
    public static var filled: FilledButtonStyle {
        .init(
            textColor: .textAction,
            textDisabledColor: .textMain.opacity(0.2),
            overlayColor: .action,
            overlayDisabledColor: .action.opacity(0.1),
            isCompact: false
        )
    }
    
    /// A full-width filled button with the primary action color (compact variant).
    public static var filledCompact: FilledButtonStyle {
        .init(
            textColor: .textAction,
            textDisabledColor: .textMain.opacity(0.2),
            overlayColor: .action,
            overlayDisabledColor: .action.opacity(0.1),
            isCompact: true
        )
    }
    
    /// A full-width filled button on the ``ShapeStyle/backgroundRow`` ground — the same tint the
    /// row and card surfaces carry, for an action that reads as one of them.
    public static var filled05: FilledButtonStyle {
        .init(
            textColor: .textMain,
            textDisabledColor: .textMain.opacity(0.2),
            overlayColor: .backgroundRow,
            overlayDisabledColor: .backgroundRow,
            isCompact: false
        )
    }
}
