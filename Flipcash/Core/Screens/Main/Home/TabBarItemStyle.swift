//
//  TabBarItemStyle.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// How the iOS 26 tab bar draws its items.
///
/// The system bar draws template glyphs and its own titles at full strength in
/// both states, so each item image carries its own colour, dimming and, unless
/// ``showsNativeTitles``, its title. The bar is left only the selection lens.
@MainActor
enum TabBarItemStyle {

    enum TitleWeight: TunableEnum { case regular, medium, semibold } // LOCAL-TUNER

    /// The point size every tab glyph is drawn at, badged or not.
    static var glyphSize: CGFloat { Tuner.shared.value("Tab bar/Icon size", default: CGFloat(28), in: 16...40, unit: .points) } // LOCAL-TUNER
    /// Moves the glyph and its title down (positive) or up within the bar.
    static var verticalOffset: CGFloat { Tuner.shared.value("Tab bar/Vertical offset", default: CGFloat(0), in: -12...12, unit: .points) } // LOCAL-TUNER
    /// The opacity of the glyph and title of the tabs that aren't selected.
    static var unselectedOpacity: Double { Tuner.shared.value("Tab bar/Unselected opacity", default: 0.5, in: 0...1) } // LOCAL-TUNER
    /// Whether the selected tab swaps to its filled glyph.
    static var fillsSelected: Bool { Tuner.shared.value("Tab bar/Fill selected icon", default: true) } // LOCAL-TUNER
    /// Whether the tabs carry titles under their glyphs.
    static var showsTitles: Bool { Tuner.shared.value("Tab bar/Show titles", default: true) } // LOCAL-TUNER
    /// Whether the titles are the system's own, which can't be dimmed, rather than drawn into the image.
    static var usesSystemTitles: Bool { Tuner.shared.value("Tab bar/System titles", default: false) } // LOCAL-TUNER
    /// The drawn title's point size.
    static var titleSize: CGFloat { Tuner.shared.value("Tab bar/Title size", default: CGFloat(10), in: 8...16, unit: .points) } // LOCAL-TUNER
    /// The drawn title's weight.
    static var titleWeight: TitleWeight { Tuner.shared.value("Tab bar/Title weight", default: TitleWeight.semibold) } // LOCAL-TUNER
    /// The space between the glyph and the drawn title.
    static var titleGap: CGFloat { Tuner.shared.value("Tab bar/Title gap", default: CGFloat(2), in: 0...16, unit: .points) } // LOCAL-TUNER
    /// The opacity of the bar's tint over its Liquid Glass.
    static var backgroundOpacity: Double { Tuner.shared.value("Tab bar/Background opacity", default: 0.5, in: 0...1) } // LOCAL-TUNER

    /// Whether the bar shows the system's titles under the item images.
    static var showsNativeTitles: Bool { showsTitles && usesSystemTitles }

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

    /// Stacks the glyph over its drawn title and pads the canvas so the bar,
    /// which centres the image, lands the pair ``verticalOffset`` from centre.
    private static func compose(_ glyph: UIImage, glyphAlpha: Double, title: String, isSelected: Bool) -> UIImage {
        let textColor = UIColor(Color.textMain).withAlphaComponent(isSelected ? 1 : unselectedOpacity)
        let text: NSAttributedString? = showsTitles && !usesSystemTitles
            ? NSAttributedString(string: title, attributes: [.font: titleFont, .foregroundColor: textColor])
            : nil

        // The glyph's alignment rect leaves out a badge's overhang, so the pair centres on the glyph.
        let insets = glyph.alignmentRectInsets
        let glyphWidth = glyph.size.width - insets.left - insets.right
        let glyphHeight = glyph.size.height - insets.top - insets.bottom
        let textSize = text.map { CGSize(width: ceil($0.size().width), height: ceil($0.size().height)) } ?? .zero

        let width = max(glyph.size.width, textSize.width)
        let contentHeight = glyph.size.height + (text == nil ? 0 : titleGap + textSize.height)
        let canvas = CGSize(width: width, height: contentHeight + 2 * abs(verticalOffset))
        let top = abs(verticalOffset) + verticalOffset

        let glyphOrigin = CGPoint(x: (width - glyphWidth) / 2 - insets.left, y: top)
        return UIGraphicsImageRenderer(size: canvas).image { _ in
            glyph.draw(at: glyphOrigin, blendMode: .normal, alpha: glyphAlpha)
            text?.draw(at: CGPoint(
                x: (width - textSize.width) / 2,
                y: top + insets.top + glyphHeight + titleGap
            ))
        }
        .withRenderingMode(.alwaysOriginal)
    }

    private static var titleFont: UIFont {
        switch titleWeight {
        case .regular:  UIFont.default(size: titleSize, weight: .regular)
        case .medium:   UIFont.default(size: titleSize, weight: .medium)
        case .semibold: UIFont.default(size: titleSize, weight: .semibold)
        }
    }
}
