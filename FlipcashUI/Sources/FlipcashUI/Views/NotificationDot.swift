//
//  NotificationDot.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI

/// A small filled dot that marks an icon as needing attention, ringed in the background colour so
/// it reads as cut out of the icon.
public struct NotificationDot: View {

    private let color: Color
    private let ring: Color
    private let size: CGFloat

    /// A dot `size` points across inside its 2pt ring.
    public init(color: Color = .unreadIndicator, ring: Color = .backgroundMain, size: CGFloat = 7) {
        self.color = color
        self.ring = ring
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            // The ring sits outside the fill: the dot plus a 2pt stroke.
            .padding(2)
            .background(Circle().fill(ring))
            .accessibilityHidden(true)
    }
}

extension View {

    /// Puts a ``NotificationDot`` on this view's top-trailing corner while `isShown` is true.
    public func notificationDot(_ isShown: Bool, color: Color = .unreadIndicator, ring: Color = .backgroundMain) -> some View {
        overlay(alignment: .topTrailing) {
            if isShown {
                NotificationDot(color: color, ring: ring)
                    .offset(x: 3, y: -3)
            }
        }
    }
}

#Preview {
    Image(systemName: "person.badge.plus")
        .font(.system(size: 17, weight: .semibold))
        .notificationDot(true)
        .padding()
        .background(Color.backgroundMain)
}
