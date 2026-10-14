//
//  MessageLinkBackChip.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import SwiftUI

/// The chip a message link leaves under the navigation bar: names the chat the link was tapped in
/// and returns to it. Values from Figma node 11493:212.
public struct MessageLinkBackChip: View {

    private let title: String
    private let action: () -> Void

    public init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .medium))
                Text(title)
                    .font(.appTextSmall)
                    .lineLimit(1)
            }
            .foregroundStyle(Color.textMain)
            .padding(.horizontal, 14)
            .frame(height: Self.height)
            .background(Color.white.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(LinkCardMetrics.borderOpacity), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to \(title)")
    }

    private static let height: CGFloat = 36
}
#endif
