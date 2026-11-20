//
//  BottomEdgePadding.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI

extension View {
    /// Pads a screen's bottom actions by `length` measured from the device's bottom edge, not from
    /// the home-indicator safe area, so the last button sits as far from the bottom as from the sides.
    ///
    /// Apply it to the view that meets the bottom of the screen, in place of its bottom padding.
    /// The keyboard still lifts the actions; only the home-indicator inset is ignored.
    ///
    /// ```swift
    /// VStack {
    ///     Spacer()
    ///     Button("Next", action: next)
    ///         .buttonStyle(.filled)
    /// }
    /// .padding([.horizontal, .top], 20)
    /// .bottomEdgePadding()
    /// ```
    public func bottomEdgePadding(_ length: CGFloat = Metrics.buttonPadding) -> some View {
        padding(.bottom, length)
            .ignoresSafeArea(.container, edges: .bottom)
    }

    /// Pads a screen whose bottom action is a `.textLink`, so the link's 44 pt tap box sits
    /// `Metrics.buttonPaddingUnderTextLink` from the device's bottom edge.
    public func bottomEdgePaddingUnderTextLink() -> some View {
        bottomEdgePadding(Metrics.buttonPaddingUnderTextLink)
    }
}

extension Metrics {
    /// The bottom padding under a screen-ending `.textLink`'s 44 pt box, which puts its text about
    /// 44 pt from the device's bottom edge, well clear of the home indicator.
    public static let buttonPaddingUnderTextLink: CGFloat = 32.0
}
