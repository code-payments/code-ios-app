//
//  SwipeActionLabel.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// A swipe action's content: the glyph in its tonal circle with the title drawn under it.
///
/// `.titleAndIcon` is what makes the row draw the title; without it a swipe action shows only the
/// glyph. The button's own `.tint` sets the circle and its `.accessibilityLabel` still names the
/// action for VoiceOver.
struct SwipeActionLabel: View {

    let title: String
    private let glyph: Glyph

    /// The glyph's colour, baked into the image because a swipe action draws its label white
    /// whatever the style says. `nil` keeps the default white outline glyph.
    var glyphColor: Color? = nil

    private enum Glyph {
        case system(String)
        case icon(Icon)
    }

    /// A label drawing the SF Symbol `systemImage`.
    init(title: String, systemImage: String, glyphColor: Color? = nil) {
        self.title = title
        self.glyph = .system(systemImage)
        self.glyphColor = glyphColor
    }

    /// A label drawing the app's Central `icon` in place of an SF Symbol.
    init(title: String, icon: Icon, glyphColor: Color? = nil) {
        self.title = title
        self.glyph = .icon(icon)
        self.glyphColor = glyphColor
    }

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Label {
            Text(title)
        } icon: {
            switch glyph {
            case .system(let systemImage):
                if let glyphColor {
                    Image(uiImage: UIImage(systemName: systemImage)!
                        .withTintColor(UIColor(glyphColor), renderingMode: .alwaysOriginal))
                } else {
                    // Swipe actions fill symbols by default; the shared design uses the outline.
                    Image(systemName: systemImage)
                        .environment(\.symbolVariants, .none)
                }
            case .icon(let icon):
                // Resolved for the appearance: a baked colour keeps the one it was drawn in.
                if let glyphColor {
                    Image.swipeAction(icon, baking: glyphColor, in: colorScheme)
                } else {
                    Image.rowSwipeAction(icon, in: colorScheme)
                }
            }
        }
        .labelStyle(.titleAndIcon)
    }
}
