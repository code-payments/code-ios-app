//
//  TabBarBadgedIcon.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// A tab glyph with its unread count drawn into the image, for the iOS 26 bar.
///
/// The system badge lives in a layer under the item image, so the Liquid Glass
/// lens that follows a drag draws the glyph over it. A count that is part of the
/// image stays on top in every state, lens included.
@MainActor
enum TabBarBadgedIcon {

    /// The slot every tab glyph is drawn into.
    private static let glyphSize: CGFloat = 32

    /// How far the bubble reaches past the glyph's top-right corner, matching
    /// the legacy pill's badge (node 8966:1846).
    private static let bubbleOverhang: CGFloat = 2

    /// Both item images for `tab` with `count` in the corner, or nil for a count
    /// of zero, which leaves the bar its plain template glyphs.
    ///
    /// Memoized on the last tab and count because this is read from a view body
    /// and each call would otherwise run two `ImageRenderer` passes.
    static func itemImages(for tab: HomeTab, count: Int) -> TabBarProfilePhoto.ItemImages? {
        guard count > 0 else { return nil }
        if let memoized, memoized.tab == tab, memoized.count == count { return memoized.images }

        guard let normal = image(of: icon(for: tab, count: count, isSelected: false)),
              let selected = image(of: icon(for: tab, count: count, isSelected: true))
        else { return nil }

        let images = TabBarProfilePhoto.ItemImages(normal: normal, selected: selected)
        memoized = (tab, count, images)
        return images
    }

    private static var memoized: (tab: HomeTab, count: Int, images: TabBarProfilePhoto.ItemImages)?

    /// The glyph colored as the bar would tint it for the state, since an
    /// original-rendered image is not tinted, with the bubble at full strength.
    private static func icon(for tab: HomeTab, count: Int, isSelected: Bool) -> some View {
        Image(tab.iconName(isSelected: isSelected))
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(glyphColor(isSelected: isSelected))
            .frame(width: glyphSize, height: glyphSize)
            .overlay(alignment: .topTrailing) {
                Bubble(size: .regular, count: count, color: .unreadIndicator)
                    .fixedSize()
                    .offset(x: bubbleOverhang, y: -bubbleOverhang)
            }
            .padding(.top, bubbleOverhang)
            .padding(.trailing, bubbleOverhang)
    }

    /// The color the bar paints its template glyphs in for the state. iOS 27
    /// ignores the unselected `iconColor` from `HomeTabView` and paints every
    /// glyph in the main text color, so the Chat glyph follows suit there.
    private static func glyphColor(isSelected: Bool) -> Color {
        if isSelected { return .textMain }
        if #available(iOS 27, *) { return .textMain }
        return .textSecondary
    }

    private static func image(of icon: some View) -> UIImage? {
        let renderer = ImageRenderer(content: icon)
        renderer.scale = UIScreen.main.scale
        // The overhang is room for the bubble, not part of the glyph, so the
        // bar lines the glyph up with its neighbours rather than the canvas.
        let overhang = UIEdgeInsets(top: bubbleOverhang, left: 0, bottom: 0, right: bubbleOverhang)
        return renderer.uiImage?
            .withAlignmentRectInsets(overhang)
            .withRenderingMode(.alwaysOriginal)
    }
}
