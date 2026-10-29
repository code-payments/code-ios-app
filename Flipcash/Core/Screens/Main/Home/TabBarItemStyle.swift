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
    /// The opacity of the glyph and title of the tabs that aren't selected.
    static let unselectedOpacity: Double = 0.5
    /// The drawn title's point size.
    static let titleSize: CGFloat = 10
    /// The space between the glyph and the drawn title.
    static let titleGap: CGFloat = 2
    /// The opacity of the bar's tint over its Liquid Glass.
    static let backgroundOpacity: Double = 0.5

    /// Whether the bar shows the system's titles, which can't be dimmed, rather than the titles drawn into each image.
    static let showsNativeTitles = false

    /// Both images the bar shows for `tab`. A profile photo or badged glyph
    /// arrives already dimmed for its state, so only its title is dimmed here.
    static func itemImages(
        for tab: HomeTab,
        profile: TabBarProfilePhoto.ItemImages?,
        badged: TabBarProfilePhoto.ItemImages?
    ) -> TabBarProfilePhoto.ItemImages {
        if let prerendered = profile ?? badged {
            return TabBarProfilePhoto.ItemImages(
                normal: compose(prerendered.normal, glyphAlpha: 1, title: tab.title, isSelected: false),
                selected: compose(prerendered.selected, glyphAlpha: 1, title: tab.title, isSelected: true)
            )
        }
        return TabBarProfilePhoto.ItemImages(
            normal: compose(glyph(for: tab, isSelected: false), glyphAlpha: unselectedOpacity, title: tab.title, isSelected: false),
            selected: compose(glyph(for: tab, isSelected: true), glyphAlpha: 1, title: tab.title, isSelected: true)
        )
    }

    /// The tab's glyph at ``glyphSize`` in the text colour.
    private static func glyph(for tab: HomeTab, isSelected: Bool) -> UIImage {
        let glyph = UIImage.icon(tab.icon(isSelected: isSelected)).withTintColor(UIColor(Color.textMain))
        let size = CGSize(width: glyphSize, height: glyphSize)
        return UIGraphicsImageRenderer(size: size).image { _ in
            glyph.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Centres the glyph in ``slotSize`` over its drawn title and pads the canvas so the bar,
    /// which centres the image, lands the pair ``verticalOffset`` from centre.
    private static func compose(_ glyph: UIImage, glyphAlpha: Double, title: String, isSelected: Bool) -> UIImage {
        let textColor = UIColor(Color.textMain).withAlphaComponent(isSelected ? 1 : unselectedOpacity)
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
