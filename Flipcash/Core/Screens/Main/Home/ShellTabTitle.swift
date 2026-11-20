//
//  ShellTabTitle.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// A Group Money shell tab's title (Groups frame, node 13729:421), in the navigation bar's
/// leading slot, so every tab that carries one draws it on the same spot. A switch into `tab`
/// fades it in over the title of the tab it left.
struct ShellTabTitle: ToolbarContent {

    let tab: HomeTab
    let title: String
    let accessibilityIdentifier: String

    var body: some ToolbarContent {
        // Plain text, so no glass behind it.
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarLeading) { label }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) { label }
        }
    }

    private var label: some View {
        ShellHeaderCrossfade(tab: tab, alignment: .leading) {
            Self.text(title)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(accessibilityIdentifier)
        } outgoing: { from in
            Self.text(HomeTabLayout.groupMoney.title(for: from))
        }
    }

    private static func text(_ title: String) -> some View {
        Text(title)
            .font(.appTitleLarge)
            // The app's bold lands on Semibold; tab titles take true Bold.
            .fontWeight(.bold)
            .foregroundStyle(Color.textMain)
            .fixedSize()
    }
}
