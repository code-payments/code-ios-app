//
//  HomeTabView.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
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
    @Environment(Container.self) private var container

    @State private var selection: HomeTab = .initial

    /// The You tab's icon, once the profile has a picture. Owned here rather
    /// than by either bar, because both bars want the same download.
    @State private var profilePhoto = TabBarProfilePhoto()

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
    /// Currency Info → Give) so that screen owns the full height, while a
    /// bill/tipcard is up (the app-root overlay owns the screen then, as the v1
    /// bill replaced the bottom bar), and while the You tab's card is expanded.
    /// Sheets already cover the bar, so only in-tab pushes need handling here.
    @State private var cardExpansion = WalletCardExpansion()
    @State private var tipCardPresentation = TipCardPresentation()

    private var isTabBarHidden: Bool {
        if cardExpansion.isExpanded { return true }
        if tipCardPresentation.isExpanded { return true }
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
            .onChange(of: selection) { _, tab in
                router.activeTabStack = tab.pushStack
                // Leaving the tab puts the card back (and the brightness with it).
                tipCardPresentation.collapse()
            }
            .onDisappear { router.activeTabStack = nil }
            // Keyed on the blob, so setting or replacing a picture reloads the
            // icon and clearing one drops it back to the glyph.
            .task(id: profilePicture?.thumbnailBlobID) {
                await profilePhoto.load(
                    profilePicture,
                    using: container.flipClient,
                    owner: sessionContainer.session.ownerKeyPair
                )
            }
    }

    private var profilePicture: ProfilePicture? {
        sessionContainer.session.profile?.profilePicture
    }

    /// What the You tab wears right now, or nil for a profile with no picture.
    ///
    /// Derived in the body rather than waited on: the profile is hydrated from
    /// the database before the first paint, so a cold launch knows a picture is
    /// coming — and can decode its BlurHash — while the thumbnail is still being
    /// read back. Keying only on the loaded photo would show the glyph until it
    /// landed, which is the tip card's icon on somebody who has a picture.
    private var profileSlot: ProfileTabSlot? {
        if let photo = profilePhoto.photo { return .photo(photo) }
        guard let picture = profilePicture, picture.thumbnailBlobID != nil else { return nil }
        return .pending(BlurHashCache.shared.image(for: picture.thumbnailBlurhash))
    }

    /// `profileSlot` in the form the iOS 26 bar takes its item images in.
    private var profileItemImages: TabBarProfilePhoto.ItemImages? {
        guard let profileSlot else { return nil }

        switch profileSlot {
        case .photo:
            return profilePhoto.itemImages
        case .pending(let preview):
            return TabBarProfilePhoto.pendingItemImages(preview: preview)
        }
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
                    tabLabel(for: tab)
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
        .background(TabBarSelectedIcons(tabs: HomeTab.allCases, profileImages: profileItemImages))
    }

    /// The unselected icon for a tab. The filled counterpart is handed to UIKit
    /// as the item's `selectedImage`, so the system owns the swap — choosing here
    /// instead would only ever be right once the selection had committed.
    ///
    /// This has to agree with what the probe writes. SwiftUI rewrites the item's
    /// image from this label whenever it rebuilds the bar, so a label that
    /// disagreed would take turns with the probe and flicker between the two.
    @ViewBuilder private func tabLabel(for tab: HomeTab) -> some View {
        if tab == .tipCard, let photo = profileItemImages?.normal {
            Image(uiImage: photo).renderingMode(.original)
        } else {
            Image(tab.iconName(isSelected: false))
        }
    }

    private static let pillBottomMargin: CGFloat = 8

    /// The room the legacy pill occupies above the safe area. The pill is an
    /// overlay, so unlike the iOS 26 system bar it adds nothing to the safe
    /// area — a tab that scrolls under it has to inset for it itself.
    static var legacyPillClearance: CGFloat { HomeTabBar.height + pillBottomMargin }

    /// iOS 18–25 fallback: the home-grown floating pill hovering over the tab
    /// content, sliding out when `isTabBarHidden`.
    private var legacyTabs: some View {
        ZStack(alignment: .bottom) {
            tabContent(for: selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)

            if !isTabBarHidden {
                HomeTabBar(
                    selection: $selection,
                    badgeCounts: [.chat: chatBadgeCount],
                    profileSlot: profileSlot
                )
                    // Figma insets the pill ~42pt from each edge (318pt wide on the
                    // 402pt frame); a fixed margin keeps the floating look across
                    // device widths.
                    .padding(.horizontal, 42)
                    .padding(.bottom, Self.pillBottomMargin)
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
            TipCardTab()
                .environment(tipCardPresentation)
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

/// The Tip Card tab — the user's own shareable tip card, plus the settings list
/// that is the tab-bar entry into My Account.
///
/// `YouScreen` renders whether or not the profile is tippable: without a display
/// name it draws the add-your-name invitation where the card would be and drops
/// the share affordances, keeping the settings rows reachable. Swapping the
/// whole screen out for a bare prompt (as this once did) stranded name-less
/// accounts with no way to reach Settings, and so no way to log out.
private struct TipCardTab: View {

    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router[.you]) {
            YouScreen()
                .appRouterDestinations()
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

    /// The You tab's photo, in place of its glyph. Passed by value so the
    /// enclosing body observes it landing and this representable is updated.
    let profileImages: TabBarProfilePhoto.ItemImages?

    func makeUIViewController(context: Context) -> Probe {
        Probe(tabs: tabs, profileImages: profileImages)
    }

    func updateUIViewController(_ probe: Probe, context: Context) {
        probe.tabs = tabs
        probe.profileImages = profileImages
        probe.apply()
    }

    final class Probe: UIViewController {
        var tabs: [HomeTab]
        var profileImages: TabBarProfilePhoto.ItemImages?

        init(tabs: [HomeTab], profileImages: TabBarProfilePhoto.ItemImages?) {
            self.tabs = tabs
            self.profileImages = profileImages
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
                if tab == .tipCard, let profileImages {
                    // Already rendered at the dimmed and full opacities the bar
                    // would otherwise get by tinting a template glyph.
                    item.image = profileImages.normal
                    item.selectedImage = profileImages.selected
                    continue
                }

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
