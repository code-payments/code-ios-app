//
//  LargeButton.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct LargeButton: View {

    private let title: String
    private let image: Image
    private let badgeCount: Int
    private let action: VoidAction

    public init(title: String, image: Image, badgeCount: Int = 0, action: @escaping VoidAction) {
        self.title      = title
        self.image      = image
        self.badgeCount = badgeCount
        self.action     = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                LargeButtonIcon(image: image, badgeCount: badgeCount)
                Text(title)
                    .font(.appTextSmall)
            }
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .bottom)
        }
        .foregroundStyle(.textMain)
        .accessibilityValue(badgeCount > 0 ? "\(badgeCount) unread" : "")
    }
}

// MARK: - Icon -

/// The 40×40 button icon. When `badgeCount > 0` it carries a count badge whose
/// pill is clipped out of the icon — a badge-shaped hole is masked away so the
/// background shows through the ring around the pill, like a native app-icon badge.
private struct LargeButtonIcon: View {

    let image: Image
    let badgeCount: Int

    private let ring: CGFloat = 2
    private let offset = CGSize(width: 14, height: -10)

    private var displayCount: Int { min(badgeCount, 100) }
    private var showsMore: Bool { badgeCount > 100 }

    var body: some View {
        let icon = image
            .resizable()
            .scaledToFit()
            .frame(width: 40, height: 40)

        if badgeCount > 0 {
            icon
                .mask(alignment: .topTrailing) {
                    // Keep the whole icon except a badge-shaped hole — the pill plus
                    // a thin ring — punched out of it. A hidden Bubble sizes the hole
                    // to the pill so it tracks the count width ("5" vs "100+").
                    Rectangle()
                        .overlay(alignment: .topTrailing) {
                            Bubble(size: .regular, count: displayCount, hasMore: showsMore)
                                .fixedSize()
                                .hidden()
                                .padding(ring)
                                .background(Capsule().fill(Color.black).blendMode(.destinationOut))
                                .offset(x: offset.width, y: offset.height)
                        }
                        .compositingGroup()
                }
                .overlay(alignment: .topTrailing) {
                    Bubble(size: .regular, count: displayCount, hasMore: showsMore, color: .unreadIndicator)
                        .fixedSize()
                        .offset(x: offset.width, y: offset.height)
                }
        } else {
            icon
        }
    }
}

// MARK: - Previews -

#Preview {
    Background(color: .backgroundMain) {
        HStack(alignment: .bottom) {
            LargeButton(title: "History", image: .asset(.history)) {}
            LargeButton(title: "Invites", image: .asset(.invites), badgeCount: 5) {}
            LargeButton(title: "Send", image: .asset(.history), badgeCount: 150) {}
        }
    }
}
