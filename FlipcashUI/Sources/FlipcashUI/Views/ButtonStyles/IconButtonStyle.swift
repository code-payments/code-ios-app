//
//  BorderedButtonStyle.swift
//  FlipcashUI
//
//  Created by Raul Riera on 2026-02-10.
//

import SwiftUI

/// A button style that displays a leading icon alongside the button's label
/// inside a translucent rounded container.
///
/// ```swift
/// Button("Website") {
///     openURL(url)
/// }
/// .buttonStyle(.icon(.web))
/// ```
public struct IconButtonStyle: ButtonStyle {
    public let icon: Asset
    
    public init(icon: Asset) {
        self.icon = icon
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image.asset(icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 18, maxHeight: 18)
            
            configuration.label
                .lineLimit(1)
                .multilineTextAlignment(.leading)
                .font(.appTextMedium)
        }
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.white.opacity(0.1))
            .cornerRadius(6)
    }
}

extension ButtonStyle where Self == IconButtonStyle {
    /// A button style that displays a leading icon alongside the label
    /// inside a translucent rounded container.
    public static func icon(_ icon: Asset) -> IconButtonStyle {
        IconButtonStyle(icon: icon)
    }
}
