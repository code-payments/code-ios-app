//
//  HomeTabBar.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// The floating pill tab bar for the v2 UI. A Liquid Glass capsule holds one
/// button per ``HomeTab``, with a selection pill that slides to the active
/// tab. Ported from Android's `NavigationBarV2` (Figma frame 9013-5434):
/// translucent capsule, ``fillSelected`` sliding indicator, text-colour icons
/// and labels in both states. Only the profile photo dims when unselected.
///
/// Drawn at one of two sizes; see ``Size``.
struct HomeTabBar: View {

    /// How big the bar is drawn.
    enum Size {
        /// The legacy pill: as wide as it is offered, 28pt icons, 58pt tall.
        case regular
        /// The iOS 26 system bar's size with two tabs, measured on a 402pt-wide
        /// iPhone: 94pt items that overlap by 8pt, 32pt icons, 188pt × 62pt for
        /// two tabs. Liquid Glass tinted like the system bar on iOS 26, with
        /// its darker selection platter.
        case compact

        /// The small bar at the leading edge, or the legacy pill centred.
        init(for alignment: HorizontalAlignment) {
            self = alignment == .leading ? .compact : .regular
        }
    }

    @Binding var selection: HomeTab

    /// Which tabs the pill holds, and what each is called and wears.
    var layout: HomeTabLayout = .standard

    var size: Size = .regular

    /// Per-tab unread badge counts; a tab absent or mapped to 0 shows no badge.
    var badgeCounts: [HomeTab: Int] = [:]

    /// The circle the You tab wears in place of its glyph, once the profile
    /// carries a picture. Nil keeps the glyph.
    var profileSlot: ProfileTabSlot?

    /// Called when a tab's button is held. The tap still selects the tab on
    /// release, so a long press lands on the tab it was made on.
    var onLongPress: ((HomeTab) -> Void)?

    private var tabs: [HomeTab] { layout.barTabs }

    // Figma tab bar (node 10642:1325): a 28pt icon over a 10pt Demi label in
    // 50pt-tall items, inside a capsule with 4pt padding → 58pt overall.
    private static let labelLineHeight: CGFloat = 12
    private static let capsulePadding: CGFloat = 4

    /// Matches `UILongPressGestureRecognizer`'s default, which the iOS 26 bar uses.
    private static let longPressDuration: TimeInterval = 0.5

    /// The pill's overall height. It floats over the tab content instead of
    /// sitting in the safe area, so a tab that scrolls has to leave room for it
    /// itself — see ``HomeTabView/legacyPillClearance``.
    static var height: CGFloat { height(.regular) }

    /// The bar's overall height at `size`.
    static func height(_ size: Size) -> CGFloat {
        Metrics(size).itemHeight + capsulePadding * 2
    }

    /// The compact bar's overall width with `tabCount` tabs: 188pt for two.
    static func compactWidth(tabCount: Int) -> CGFloat {
        let metrics = Metrics(.compact)
        let itemWidth = metrics.itemWidth ?? 0
        return capsulePadding * 2 + itemWidth + CGFloat(max(0, tabCount - 1)) * (itemWidth - metrics.itemOverlap)
    }

    /// What differs between the two sizes.
    private struct Metrics {
        let itemHeight: CGFloat
        let iconSize: CGFloat
        /// Nil shares the offered width equally between the items.
        let itemWidth: CGFloat?
        /// How far neighbouring items, and so the selection platter's two
        /// resting places, overlap.
        let itemOverlap: CGFloat
        /// Between the icon's frame and the label's.
        let labelSpacing: CGFloat
        /// From the item's top to the icon's; nil centres icon and label.
        let iconTopInset: CGFloat?

        init(_ size: Size) {
            switch size {
            case .regular:
                itemHeight = 50
                iconSize = 28
                itemWidth = nil
                itemOverlap = 0
                labelSpacing = 0
                iconTopInset = nil
            case .compact:
                // The system bar's platter is 94pt × 54pt, 4pt inside the
                // glass; its icon frame starts 4pt below the platter's top
                // and its label frame overlaps the icon's by 1pt.
                itemHeight = 54
                iconSize = 32
                itemWidth = 94
                itemOverlap = 8
                labelSpacing = -1
                iconTopInset = 4
            }
        }
    }

    var body: some View {
        let metrics = Metrics(size)
        GeometryReader { proxy in
            let itemWidth = metrics.itemWidth ?? proxy.size.width / CGFloat(tabs.count)
            let stride = itemWidth - metrics.itemOverlap
            let selectedIndex = tabs.firstIndex(of: selection) ?? 0

            ZStack(alignment: .leading) {
                // Selected-state pill, drawn behind the icons, sliding to the active tab.
                Capsule()
                    .fill(platterColor)
                    .frame(width: itemWidth, height: metrics.itemHeight)
                    .offset(x: stride * CGFloat(selectedIndex))
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selection)

                HStack(spacing: -metrics.itemOverlap) {
                    ForEach(tabs) { tab in
                        Button {
                            selection = tab
                        } label: {
                            VStack(spacing: metrics.labelSpacing) {
                                icon(for: tab, size: metrics.iconSize)
                                    .overlay(alignment: .topTrailing) {
                                        if let count = badgeCounts[tab], count > 0 {
                                            Bubble(size: .regular, count: count, color: .unreadIndicator)
                                            .fixedSize()
                                            // Overlap the icon's top-right corner to
                                            // match the native bar's badge placement.
                                            .offset(x: 2, y: -2)
                                            .accessibilityHidden(true)
                                        }
                                    }

                                Text(layout.title(for: tab))
                                    .font(.default(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.textMain)
                                    .lineLimit(1)
                                    .frame(height: Self.labelLineHeight)
                                    .accessibilityHidden(true)
                            }
                            .padding(.top, metrics.iconTopInset ?? 0)
                            .frame(
                                width: itemWidth,
                                height: metrics.itemHeight,
                                alignment: metrics.iconTopInset == nil ? .center : .top
                            )
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        // Simultaneous, not high-priority: a high-priority long
                        // press holds the button's tap hostage until it fails,
                        // which made quick taps unreliable.
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: Self.longPressDuration)
                                .onEnded { _ in onLongPress?(tab) }
                        )
                        .accessibilityLabel(layout.title(for: tab))
                        .accessibilityValue((badgeCounts[tab] ?? 0) > 0 ? "\(badgeCounts[tab] ?? 0) unread" : "")
                        .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
                    }
                }
            }
        }
        .frame(width: contentWidth, height: metrics.itemHeight)
        .padding(Self.capsulePadding)
        .modifier(BarGlass(size: size))
    }

    /// Fixed for the compact bar; the regular bar takes the width it is offered.
    private var contentWidth: CGFloat? {
        guard size == .compact else { return nil }
        return Self.compactWidth(tabCount: tabs.count) - Self.capsulePadding * 2
    }

    /// The compact bar's platter is darker than its glass on iOS 26, as the
    /// system bar's is; everywhere else it is the pill's white 20%.
    private var platterColor: Color {
        if #available(iOS 26, *), size == .compact {
            return Color.black.opacity(0.45)
        }
        return Color.fillSelected
    }

    /// The You tab draws the profile picture once there is one; every other tab,
    /// and a profile without a picture, keeps the outline glyph.
    @ViewBuilder
    private func icon(for tab: HomeTab, size iconSize: CGFloat) -> some View {
        if tab == .tipCard, let profileSlot {
            ProfileTabIcon(photo: profileSlot.preview, isSelected: tab == selection)
                .opacity(tab == selection ? 1 : 0.5)
                .scaleEffect(iconSize / ProfileTabIcon.slotSize)
                .frame(width: iconSize, height: iconSize)
        } else {
            Image.icon(layout.icon(for: tab, isSelected: tab == selection))
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .foregroundStyle(Color.textMain)
        }
    }
}

/// The bar's capsule. The regular pill keeps the app's capsule glass. The
/// compact bar stands in for the iOS 26 system bar, so there it takes that
/// bar's tint (the shell's `backgroundMain` at 50%) and is not interactive,
/// since interactive glass on a container competes with its buttons for the
/// tap. Before iOS 26 both sizes use the same material.
private struct BarGlass: ViewModifier {
    let size: HomeTabBar.Size

    func body(content: Content) -> some View {
        if #available(iOS 26, *), size == .compact {
            content
                .glassEffect(.regular.tint(Color.backgroundMain.opacity(0.5)), in: Capsule())
                // Read as a tab bar, as the system bar's items are.
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isTabBar)
        } else if size == .compact {
            content
                .capsuleGlassBackground()
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isTabBar)
        } else {
            content.capsuleGlassBackground()
        }
    }
}
