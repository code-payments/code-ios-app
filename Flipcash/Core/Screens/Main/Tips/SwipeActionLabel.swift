//
//  SwipeActionLabel.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// A swipe action's content: the symbol in its tonal circle with the title drawn under it.
///
/// `.titleAndIcon` is what makes the row draw the title; without it a swipe action shows only the
/// symbol. The button's own `.tint` sets the circle and its `.accessibilityLabel` still names the
/// action for VoiceOver.
struct SwipeActionLabel: View {

    let title: String
    let systemImage: String

    /// The glyph's colour, baked into the image because a swipe action draws its label white
    /// whatever the style says. `nil` keeps the default white outline glyph.
    var glyphColor: Color? = nil

    var body: some View {
        Label {
            Text(title)
        } icon: {
            if let glyphColor {
                Image(uiImage: UIImage(systemName: systemImage)!
                    .withTintColor(UIColor(glyphColor), renderingMode: .alwaysOriginal))
            } else {
                // Swipe actions fill symbols by default; the shared design uses the outline.
                Image(systemName: systemImage)
                    .environment(\.symbolVariants, .none)
            }
        }
        .labelStyle(.titleAndIcon)
    }
}
