//
//  BorderedButtonStyle.swift
//  FlipcashUI
//
//  Created by Raul Riera on 2026-02-10.
//

import SwiftUI

/// A button style that displays a leading icon alongside the button's label
/// inside a translucent capsule.
///
/// ```swift
/// Button("Website") {
///     openURL(url)
/// }
/// .buttonStyle(.icon(.web))
/// ```
public struct IconButtonStyle: ButtonStyle {
    public let icon: Image
    
    public init(icon: Asset) {
        self.icon = Image.asset(icon)
    }

    /// Creates the style with a Central icon.
    public init(icon: Icon) {
        self.icon = Image.icon(icon)
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 10) {
            icon
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 18, maxHeight: 18)
            
            configuration.label
                .lineLimit(1)
                .multilineTextAlignment(.leading)
                .font(.appTextMedium)
        }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.actionSecondary)
            .clipShape(Capsule())
            .buttonPress(isPressed: configuration.isPressed)
    }
}

extension ButtonStyle where Self == IconButtonStyle {
    /// A button style that displays a leading icon alongside the label
    /// inside a translucent capsule.
    public static func icon(_ icon: Asset) -> IconButtonStyle {
        IconButtonStyle(icon: icon)
    }

    /// A button style that displays a leading Central icon alongside the label
    /// inside a translucent capsule.
    public static func icon(_ icon: Icon) -> IconButtonStyle {
        IconButtonStyle(icon: icon)
    }
}
