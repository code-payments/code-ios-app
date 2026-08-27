//
//  HomeTabBar.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// The floating pill tab bar for the v2 UI. A Liquid Glass capsule holds one
/// button per ``HomeTab``, with a white selection pill that slides to the active
/// tab. Ported from Android's `NavigationBarV2` (Figma frame 9013-5434):
/// translucent capsule, white-20% sliding indicator, icons at full/half opacity.
struct HomeTabBar: View {

    @Binding var selection: HomeTab

    /// Per-tab unread badge counts; a tab absent or mapped to 0 shows no badge.
    var badgeCounts: [HomeTab: Int] = [:]

    /// The signed-in profile's picture, which the You tab wears in place of its
    /// glyph. Nil keeps the glyph.
    var profilePhoto: UIImage?

    private let tabs = HomeTab.allCases

    // Figma tab bar (node 8966:1557): 32pt icons in 50pt-tall items (9pt above
    // and below), inside a capsule with 4pt padding → 58pt overall.
    private static let itemVerticalPadding: CGFloat = 9
    private static let iconSize: CGFloat = 32
    private static let capsulePadding: CGFloat = 4

    private static var itemHeight: CGFloat { iconSize + itemVerticalPadding * 2 }

    /// The pill's overall height. It floats over the tab content instead of
    /// sitting in the safe area, so a tab that scrolls has to leave room for it
    /// itself — see ``HomeTabView/legacyPillClearance``.
    static var height: CGFloat { itemHeight + capsulePadding * 2 }

    var body: some View {
        GeometryReader { proxy in
            let itemWidth = proxy.size.width / CGFloat(tabs.count)
            let selectedIndex = tabs.firstIndex(of: selection) ?? 0

            ZStack(alignment: .leading) {
                // Selected-state pill, drawn behind the icons, sliding to the active tab.
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: itemWidth, height: Self.itemHeight)
                    .offset(x: itemWidth * CGFloat(selectedIndex))
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selection)

                HStack(spacing: 0) {
                    ForEach(tabs) { tab in
                        Button {
                            selection = tab
                        } label: {
                            icon(for: tab)
                                .opacity(selection == tab ? 1 : 0.5)
                                .overlay(alignment: .topTrailing) {
                                    if let count = badgeCounts[tab], count > 0 {
                                        Bubble(
                                            size: .regular,
                                            count: min(count, 100),
                                            hasMore: count > 100,
                                            color: .unreadIndicator
                                        )
                                        .fixedSize()
                                        // Overlap the icon's top-right corner to
                                        // match the native bar's badge placement.
                                        .offset(x: 2, y: -2)
                                        .accessibilityHidden(true)
                                    }
                                }
                                .frame(width: itemWidth, height: Self.itemHeight)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tab.accessibilityLabel)
                        .accessibilityValue((badgeCounts[tab] ?? 0) > 0 ? "\(badgeCounts[tab] ?? 0) unread" : "")
                        .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
                    }
                }
            }
        }
        .frame(height: Self.itemHeight)
        .padding(Self.capsulePadding)
        .capsuleGlassBackground()
    }

    /// The You tab draws the profile picture once there is one; every other tab,
    /// and a profile without a picture, keeps the outline glyph.
    @ViewBuilder
    private func icon(for tab: HomeTab) -> some View {
        if tab == .tipCard, let profilePhoto {
            ProfileTabIcon(photo: profilePhoto)
        } else {
            Image(tab.iconName(isSelected: tab == selection))
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: Self.iconSize, height: Self.iconSize)
                .foregroundStyle(Color.white)
        }
    }
}

private extension View {
    /// The app's Liquid Glass surface clipped to a capsule — Liquid Glass on
    /// iOS 26, an ultra-thin material below (mirrors `glassBackground(cornerRadius:)`,
    /// which only offers a rounded-rect).
    @ViewBuilder
    func capsuleGlassBackground() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.interactive(), in: Capsule())
        } else {
            background(.ultraThinMaterial, in: Capsule())
        }
    }
}
