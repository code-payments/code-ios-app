//
//  ShellTabTitle.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// A Group Money shell tab's title (Groups frame, node 13729:421), in the navigation bar's
/// leading slot, so every tab that carries one draws it on the same spot.
struct ShellTabTitle: ToolbarContent {

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
        Text(title)
            .font(.appTitleLarge)
            .foregroundStyle(Color.textMain)
            .fixedSize()
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(accessibilityIdentifier)
    }
}
