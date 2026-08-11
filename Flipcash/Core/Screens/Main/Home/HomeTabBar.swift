//
//  HomeTabBar.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// The floating pill tab bar for the v2 UI. A dark translucent capsule holds one
/// button per ``HomeTab``, with a white selection pill that slides to the active
/// tab. Ported from Android's `NavigationBarV2` (Figma frame 9013-5434): black
/// 62%-alpha capsule, white-20% sliding indicator, icons at full/half opacity.
struct HomeTabBar: View {

    @Binding var selection: HomeTab

    private let tabs = HomeTab.allCases

    /// Vertical padding inside the capsule around each item.
    private let itemVerticalPadding: CGFloat = 8
    private let iconSize: CGFloat = 24

    private var itemHeight: CGFloat { iconSize + itemVerticalPadding * 2 }

    var body: some View {
        GeometryReader { proxy in
            let itemWidth = proxy.size.width / CGFloat(tabs.count)
            let selectedIndex = tabs.firstIndex(of: selection) ?? 0

            ZStack(alignment: .leading) {
                // Selected-state pill, drawn behind the icons, sliding to the active tab.
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: itemWidth, height: itemHeight)
                    .offset(x: itemWidth * CGFloat(selectedIndex))
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selection)

                HStack(spacing: 0) {
                    ForEach(tabs) { tab in
                        Button {
                            selection = tab
                        } label: {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: iconSize * 0.72, weight: .semibold))
                                .foregroundStyle(Color.white)
                                .opacity(selection == tab ? 1 : 0.5)
                                .frame(width: itemWidth, height: itemHeight)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tab.accessibilityLabel)
                        .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
                    }
                }
            }
        }
        .frame(height: itemHeight)
        .padding(4)
        .background(Color.black.opacity(0.62), in: Capsule())
    }
}
