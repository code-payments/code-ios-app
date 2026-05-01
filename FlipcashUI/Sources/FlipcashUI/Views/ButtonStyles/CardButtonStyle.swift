//
//  CardButtonStyle.swift
//  FlipcashUI
//
//  Created by Raul Riera on 2026-04-30.
//

import SwiftUI

/// A square card button with a centered icon stacked above its label,
/// inside a translucent rounded container. Pairs well in horizontal
/// stacks of two for primary tile-style entry points.
///
/// ```swift
/// Button("Deposit") {
///     deposit()
/// }
/// .buttonStyle(.card(icon: .deposit))
/// ```
public struct CardButtonStyle: ButtonStyle {
    public let icon: Asset

    public init(icon: Asset) {
        self.icon = icon
    }

    public func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 12) {
            Image.asset(icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)

            configuration.label
                .lineLimit(1)
                .font(.appTextMedium)
                .foregroundStyle(Color.textMain)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 110)
        .background(.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Metrics.boxRadius))
        .opacity(configuration.isPressed ? 0.6 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == CardButtonStyle {
    /// A square card button with a centered icon above its label.
    public static func card(icon: Asset) -> CardButtonStyle {
        CardButtonStyle(icon: icon)
    }
}
