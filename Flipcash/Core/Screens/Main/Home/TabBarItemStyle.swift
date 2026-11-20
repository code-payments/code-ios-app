//
//  TabBarItemStyle.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// How the iOS 26 tab bar draws its items.
///
/// The system bar draws template glyphs and its own titles at full strength in
/// both states, so each item image carries its own colour, dimming and title.
/// The bar is left only the selection lens.
@MainActor
enum TabBarItemStyle {

    /// The point size every tab glyph is drawn at, badged or not.
    static let glyphSize: CGFloat = 28
    /// The square every tab image is centred in above its title: the profile photo's slot, which
    /// also leaves room for a badge's overhang, so every title sits on one line.
    static let slotSize: CGFloat = ProfileTabIcon.slotSize
    /// Moves the glyph and its title down (positive) or up within the bar.
    static let verticalOffset: CGFloat = 0
    /// The opacity of the glyph and title of the tabs that aren't selected, on a bar drawn for
    /// `colorScheme`: 0.5 holds 5.35:1 on the dark bar; the white glass needs 0.6 for 5.74:1.
    nonisolated static func unselectedOpacity(for colorScheme: ColorScheme) -> Double {
        colorScheme == .dark ? 0.5 : 0.6
    }
    /// The drawn title's point size.
    static let titleSize: CGFloat = 10
    /// The space between the glyph and the drawn title.
    static let titleGap: CGFloat = 2
    /// The opacity of the bar's tint over its Liquid Glass.
    static let backgroundOpacity: Double = 0.5

    /// Whether the bar shows the system's titles, which can't be dimmed, rather than the titles drawn into each image.
    static let showsNativeTitles = false

    /// Both images the bar shows for `tab` in `layout`, titled and glyphed for that layout and
    /// drawn for `colorScheme`. A profile photo or badged glyph arrives already dimmed and coloured
    /// for its state, so only its title is drawn here.
    static func itemImages(
        for tab: HomeTab,
        layout: HomeTabLayout = .standard,
        profile: TabBarProfilePhoto.ItemImages?,
        badged: TabBarProfilePhoto.ItemImages?,
        colorScheme: ColorScheme
    ) -> TabBarProfilePhoto.ItemImages {
        let title = layout.title(for: tab)
        let ink = ink(for: colorScheme)
        let dim = unselectedOpacity(for: colorScheme)
        if let prerendered = profile ?? badged {
            return TabBarProfilePhoto.ItemImages(
                normal: compose(prerendered.normal, glyphAlpha: 1, title: title, titleAlpha: dim, ink: ink),
                selected: compose(prerendered.selected, glyphAlpha: 1, title: title, titleAlpha: 1, ink: ink)
            )
        }
        return TabBarProfilePhoto.ItemImages(
            normal: compose(glyph(for: tab, layout: layout, isSelected: false, ink: ink), glyphAlpha: dim, title: title, titleAlpha: dim, ink: ink),
            selected: compose(glyph(for: tab, layout: layout, isSelected: true, ink: ink), glyphAlpha: 1, title: title, titleAlpha: 1, ink: ink)
        )
    }

    /// The bar's tint over its Liquid Glass: `backgroundMain` at ``backgroundOpacity`` as it resolves in
    /// `colorScheme`, so the bar can wear dark over the scanner while the app is light.
    static func background(for colorScheme: ColorScheme) -> Color {
        Color(uiColor: UIColor(Color.backgroundMain).resolvedColor(with: traits(for: colorScheme)))
            .opacity(backgroundOpacity)
    }

    /// The text colour as it resolves in `colorScheme`, since a drawn image keeps the colour it was drawn in.
    private static func ink(for colorScheme: ColorScheme) -> UIColor {
        UIColor(Color.textMain).resolvedColor(with: traits(for: colorScheme))
    }

    private static func traits(for colorScheme: ColorScheme) -> UITraitCollection {
        UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
    }

    /// The tab's glyph in `layout` at ``glyphSize`` in `ink`.
    private static func glyph(for tab: HomeTab, layout: HomeTabLayout, isSelected: Bool, ink: UIColor) -> UIImage {
        let glyph = UIImage.icon(layout.icon(for: tab, isSelected: isSelected)).withTintColor(ink)
        let size = CGSize(width: glyphSize, height: glyphSize)
        return UIGraphicsImageRenderer(size: size).image { _ in
            glyph.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Centres the glyph in ``slotSize`` over its drawn title and pads the canvas so the bar,
    /// which centres the image, lands the pair ``verticalOffset`` from centre.
    private static func compose(_ glyph: UIImage, glyphAlpha: Double, title: String, titleAlpha: Double, ink: UIColor) -> UIImage {
        let textColor = ink.withAlphaComponent(titleAlpha)
        let text = NSAttributedString(string: title, attributes: [.font: titleFont, .foregroundColor: textColor])

        // The glyph's alignment rect leaves out a badge's overhang, so the slot centres on the glyph.
        let insets = glyph.alignmentRectInsets
        let glyphWidth = glyph.size.width - insets.left - insets.right
        let glyphHeight = glyph.size.height - insets.top - insets.bottom
        let textSize = CGSize(width: ceil(text.size().width), height: ceil(text.size().height))

        let width = max(slotSize, textSize.width)
        let contentHeight = slotSize + titleGap + textSize.height
        let canvas = CGSize(width: width, height: contentHeight + 2 * abs(verticalOffset))
        let top = abs(verticalOffset) + verticalOffset

        let glyphOrigin = CGPoint(
            x: (width - glyphWidth) / 2 - insets.left,
            y: top + (slotSize - glyphHeight) / 2 - insets.top
        )
        return UIGraphicsImageRenderer(size: canvas).image { _ in
            glyph.draw(at: glyphOrigin, blendMode: .normal, alpha: glyphAlpha)
            text.draw(at: CGPoint(
                x: (width - textSize.width) / 2,
                y: top + slotSize + titleGap
            ))
        }
        .withRenderingMode(.alwaysOriginal)
    }

    private static let titleFont = UIFont.default(size: titleSize, weight: .semibold)
}
