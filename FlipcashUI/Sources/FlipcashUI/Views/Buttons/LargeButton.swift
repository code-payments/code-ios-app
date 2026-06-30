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

/// The 40×40 button icon. When `badgeCount > 0` it carries a count badge that is
/// clipped out of the icon: the pill draws over a `destinationOut` capsule that
/// erases a ring around it, so the background shows through — like a native
/// app-icon badge. The pill and its hole are one view, so they scale and fade
/// together as the badge transitions in and out.
private struct LargeButtonIcon: View {

    let image: Image
    let badgeCount: Int

    /// Resting scale of the pill and the transparent gap punched around it.
    private let badgeScale: CGFloat = 1.275
    private let ring: CGFloat = 3
    private let offset = CGSize(width: 14, height: -10)

    /// Holds the last non-zero count so the pill keeps showing it while it
    /// animates out, instead of flashing "0".
    @State private var shownCount = 0

    private var displayCount: Int { min(shownCount, 100) }
    private var showsMore: Bool { shownCount > 100 }
    private var isVisible: Bool { badgeCount > 0 }

    var body: some View {
        image
            .resizable()
            .scaledToFit()
            .frame(width: 40, height: 40)
            .overlay(alignment: .topTrailing) {
                Bubble(size: .regular, count: displayCount, hasMore: showsMore, color: .unreadIndicator)
                    .fixedSize()
                    .padding(ring)
                    .background(Capsule().fill(Color.black).blendMode(.destinationOut))
                    // Explicit scaleEffect anchored on the pill's own center so it
                    // grows/shrinks in place. (`.transition(.scale)` here anchors on
                    // the compositingGroup's bounds — the whole icon — and drifts.)
                    .scaleEffect(isVisible ? badgeScale : 0, anchor: .center)
                    .opacity(isVisible ? 1 : 0)
                    .offset(x: offset.width, y: offset.height)
            }
            // Scopes the `destinationOut` erase to the icon + badge only, so the
            // ring punches through the icon rather than the screen behind it.
            .compositingGroup()
            .animation(.bouncy, value: badgeCount > 0)
            .onChange(of: badgeCount, initial: true) { _, newValue in
                if newValue > 0 { shownCount = newValue }
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
