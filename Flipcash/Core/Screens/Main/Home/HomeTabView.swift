//
//  HomeTabView.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// The post-login root. Hosts the four tabs, launches on Wallet, and owns the
/// app-level `router.rootSheet` host so `router.present(_:)` works from any tab.
///
/// On iOS 26 the tabs live in a native `TabView`, which renders the system
/// Liquid Glass tab bar; below that we fall back to the home-grown floating
/// `HomeTabBar` pill. The native `TabView` keeps every tab alive, so the Scan
/// tab's camera is gated on `selection` (rather than relying on `onDisappear`)
/// to tear down when it isn't the active tab. The selected tab's push target is
/// published to the router via `activeTabStack`, since a tab is the active
/// surface without being a sheet.
struct HomeTabView: View {

    @Environment(AppRouter.self) private var router
    @Environment(SessionContainer.self) private var sessionContainer

    @State private var selection: HomeTab = .initial

    init() {
        // Color the tab glyphs per state: selected white, the rest secondary.
        // The iOS 26 tab bar ignores UITabBar.unselectedItemTintColor, so drive
        // it through a full item appearance instead. A transparent background
        // keeps the system's Liquid Glass. No-op on the legacy pill path, which
        // draws its own buttons rather than a `UITabBar`.
        if #available(iOS 26, *) {
            let items = UITabBarItemAppearance()
            items.normal.iconColor = UIColor(Color.textSecondary)
            items.selected.iconColor = UIColor(Color.textMain)
            // The unread-chat badge uses the app's blue indicator, not the
            // system tab bar's default red.
            items.normal.badgeBackgroundColor = UIColor(Color.unreadIndicator)
            items.selected.badgeBackgroundColor = UIColor(Color.unreadIndicator)
            // Nudge the system badge down onto the glyph's top-right corner to match
            // the Figma spec (node 8966:1846); by default it floats detached above.
            let badgeOffset = UIOffset(horizontal: 10, vertical: 8)
            items.normal.badgePositionAdjustment = badgeOffset
            items.selected.badgePositionAdjustment = badgeOffset

            let appearance = UITabBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.stackedLayoutAppearance = items
            appearance.inlineLayoutAppearance = items
            appearance.compactInlineLayoutAppearance = items

            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }

    /// Hide the tab bar whenever the active tab has pushed a screen (e.g. Wallet →
    /// Currency Info → Give) so that screen owns the full height, and while a
    /// bill/tipcard is up (the app-root overlay owns the screen then, as the v1
    /// bill replaced the bottom bar). Sheets already cover the bar, so only
    /// in-tab pushes need handling here.
    @State private var cardExpansion = WalletCardExpansion()

    private var isTabBarHidden: Bool {
        if cardExpansion.isExpanded { return true }
        if sessionContainer.session.isShowingBill { return true }
        guard let stack = selection.pushStack else { return false }
        return !router[stack].isEmpty
    }

    /// Unread tip-conversation count, surfaced as a badge on the Chat tab —
    /// mirrors the v1 scanner's Tips button badge. Reactive: reads the
    /// `@Observable` conversation store, so the badge updates as chats are read.
    private var chatBadgeCount: Int {
        sessionContainer.conversationController.unreadConversationCount(of: .tipDm)
    }

    var body: some View {
        tabs
            .background(Color.backgroundMain)
            // The app-level sheet host, so `router.present(_:)` works from any tab.
            .modifier(RootSheetHostModifier())
            .onAppear {
                router.activeTabStack = selection.pushStack
                // A deep link that landed before this view started observing
                // (cold start into a tab route) parked its request on the router;
                // consume it here so it isn't dropped.
                selectRequestedTab()
            }
            .onChange(of: router.requestedTabStack) { _, _ in selectRequestedTab() }
            .onChange(of: selection) { _, tab in router.activeTabStack = tab.pushStack }
            .onDisappear { router.activeTabStack = nil }
    }

    /// Brings the tab the router asked for forward and clears the request.
    private func selectRequestedTab() {
        guard let requested = router.requestedTabStack,
              let tab = HomeTab.allCases.first(where: { $0.pushStack == requested })
        else { return }
        selection = tab
        router.requestedTabStack = nil
    }

    @ViewBuilder private var tabs: some View {
        if #available(iOS 26, *) {
            nativeTabs
        } else {
            legacyTabs
        }
    }

    /// iOS 26+: the system Liquid Glass tab bar via a native `TabView`. The bar is
    /// hidden reactively (rather than by a slide-out transition) so the drill-in /
    /// bill-showing behavior matches the legacy pill.
    @available(iOS 26, *)
    private var nativeTabs: some View {
        TabView(selection: $selection) {
            ForEach(HomeTab.allCases) { tab in
                Tab(value: tab) {
                    tabContent(for: tab)
                        .toolbar(isTabBarHidden ? .hidden : .visible, for: .tabBar)
                } label: {
                    // Always the outline. The filled counterpart is handed to
                    // UIKit below as the item's `selectedImage`, so the system
                    // owns the swap — choosing here instead would only ever be
                    // right once the selection had committed.
                    Image(tab.iconName(isSelected: false))
                        .accessibilityLabel(tab.accessibilityLabel)
                }
                // Unread-chat count on the Chat tab; a count of 0 hides the badge.
                .badge(tab == .chat ? chatBadgeCount : 0)
            }
        }
        // Selected-tab highlight over a lightly tinted glass bar — echoes the old
        // pill's white indicator on a translucent capsule.
        .tint(Color.textMain)
        .toolbarBackground(Color.backgroundMain.opacity(0.5), for: .tabBar)
        // Gives each item both of its glyphs. The tab bar knows which item the
        // Liquid Glass pill is over mid-drag and renders that one selected, so
        // handing it the pair is what makes the icons fill under the finger
        // rather than when the drag commits — the binding does not change until
        // the finger lifts.
        .background(TabBarSelectedIcons(tabs: HomeTab.allCases))
    }

    /// iOS 18–25 fallback: the home-grown floating pill hovering over the tab
    /// content, sliding out when `isTabBarHidden`.
    private var legacyTabs: some View {
        ZStack(alignment: .bottom) {
            tabContent(for: selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)

            if !isTabBarHidden {
                HomeTabBar(selection: $selection, badgeCounts: [.chat: chatBadgeCount])
                    // Figma insets the pill ~42pt from each edge (318pt wide on the
                    // 402pt frame); a fixed margin keeps the floating look across
                    // device widths.
                    .padding(.horizontal, 42)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selection)
        .animation(.easeInOut(duration: 0.2), value: isTabBarHidden)
    }

    /// The content for a given tab. The Scan tab is gated on `selection` so its
    /// camera tears down when the tab isn't active — the native `TabView` keeps
    /// every tab alive, so an `onDisappear` alone wouldn't stop it.
    @ViewBuilder private func tabContent(for tab: HomeTab) -> some View {
        switch tab {
        case .scan:
            if selection == .scan {
                ScanScreen()
            } else {
                Color.backgroundMain
            }
        case .wallet:
            WalletScreen(onScanTipCard: { selection = .scan })
                .environment(cardExpansion)
        case .chat:
            ChatTab()
        case .tipCard:
            TipCardTab(onSetUp: { selection = .chat })
        }
    }
}

extension HomeTab {
    /// The router stack this tab pushes onto, published to `AppRouter` as the
    /// active push target. `nil` for tabs that only present sheets (Scan) or
    /// never push (Tip Card owns a local stack).
    ///
    /// Must agree with `AppRouter.Stack.isTabHosted`, which is what the router
    /// routes on; `AppRouterCrossStackTests` pins the two together.
    var pushStack: AppRouter.Stack? {
        switch self {
        case .wallet:  return .balance
        case .chat:    return .tips
        case .tipCard: return .you
        case .scan:    return nil
        }
    }
}

// MARK: - Chat tab -

/// The Chat tab — the tip conversations surface. Mirrors `TipsSheetRoot` (the
/// `.tips` sheet) as embedded tab chrome: the same `NavigationStack` bound to
/// `router[.tips]` and the same profile-creation state, minus the sheet's close
/// button.
private struct ChatTab: View {

    @Environment(AppRouter.self) private var router
    @State private var creationState = ProfileCreationState()

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router[.tips]) {
            TipsScreen(isEmbedded: true)
                .appRouterDestinations()
        }
        .environment(creationState)
    }
}

// MARK: - Tip Card tab -

/// The Tip Card tab — the user's own shareable tip card. Only tippable profiles
/// have a card; before then it prompts the user over to the Chat tab, where the
/// add-your-name flow lives (avoiding a duplicate profile-creation push here).
private struct TipCardTab: View {

    @Environment(AppRouter.self) private var router
    @Environment(SessionContainer.self) private var sessionContainer

    let onSetUp: () -> Void

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router[.you]) {
            Group {
                if sessionContainer.session.profile?.isTippable == true {
                    YouScreen()
                } else {
                    TipCardSetupPrompt(onSetUp: onSetUp)
                }
            }
            .appRouterDestinations()
        }
    }
}

/// Shown on the Tip Card tab before the user has a tippable profile.
private struct TipCardSetupPrompt: View {

    let onSetUp: () -> Void

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 12) {
                Text("Set Up Your Tip Card")
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)

                Text("Add your name to get a tip card you can share and receive tips.")
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)

                BubbleButton(text: "Get Started") { onSetUp() }
                    .padding(.top, 8)
            }
            .padding(.horizontal, 40)
        }
    }
}

/// Hands each tab bar item its selected glyph, which SwiftUI's `Tab` has no API
/// for.
///
/// The point is *when* the swap happens. SwiftUI can only pick a glyph from the
/// selection binding, and the system does not write that back until a drag of
/// the Liquid Glass pill commits — so a binding-driven icon stays outlined until
/// the finger lifts. `UITabBarItem` holds both glyphs at once and the bar draws
/// whichever matches the pill's live position, which is how the system's own
/// tabs fill as you drag across them.
///
/// Reaching the item means reaching the `UITabBarController` SwiftUI builds for
/// us; there is no supported route to it, hence the probe. It re-applies on
/// every update because SwiftUI resets the images when it rebuilds the bar.
@available(iOS 26, *)
private struct TabBarSelectedIcons: UIViewControllerRepresentable {
    let tabs: [HomeTab]

    func makeUIViewController(context: Context) -> Probe { Probe(tabs: tabs) }

    func updateUIViewController(_ probe: Probe, context: Context) {
        probe.tabs = tabs
        probe.apply()
    }

    final class Probe: UIViewController {
        var tabs: [HomeTab]

        init(tabs: [HomeTab]) {
            self.tabs = tabs
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            apply()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            apply()
        }

        /// Quietly does nothing if the bar is not there yet or does not line up
        /// with the tabs — the icons then simply stay outlined, rather than the
        /// wrong glyph being pinned to the wrong tab. Retried on the next turn
        /// of the runloop, because the bar's items do not exist yet on the pass
        /// where this controller is first added.
        func apply() {
            guard let items = resolvedTabBar?.items, items.count == tabs.count else {
                scheduleRetry()
                return
            }

            for (item, tab) in zip(items, tabs) {
                item.image = UIImage(named: tab.iconName(isSelected: false))?
                    .withRenderingMode(.alwaysTemplate)
                item.selectedImage = UIImage(named: tab.iconName(isSelected: true))?
                    .withRenderingMode(.alwaysTemplate)
            }
        }

        private var hasRetryScheduled = false

        private func scheduleRetry() {
            guard !hasRetryScheduled else { return }
            hasRetryScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.hasRetryScheduled = false
                self?.apply()
            }
        }

        /// This controller is attached alongside the `TabView` rather than inside
        /// a tab, so `tabBarController` is nil — the bar has to be found from the
        /// window instead.
        private var resolvedTabBar: UITabBar? {
            if let bar = tabBarController?.tabBar { return bar }
            guard let root = view.window?.rootViewController else { return nil }

            var queue: [UIViewController] = [root]
            while let next = queue.first {
                queue.removeFirst()
                if let tabs = next as? UITabBarController { return tabs.tabBar }
                queue.append(contentsOf: next.children)
                if let presented = next.presentedViewController { queue.append(presented) }
            }
            return nil
        }
    }
}
