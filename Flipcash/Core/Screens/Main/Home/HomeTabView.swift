//
//  HomeTabView.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The post-login root. Hosts the four tabs, opens on `HomeTab.initial`, and owns the
/// app-level `router.rootSheet` host so `router.present(_:)` works from any tab.
///
/// On iOS 26 the tabs live in a native `TabView`, which renders the system
/// Liquid Glass tab bar; below that we fall back to the home-grown floating
/// `HomeTabBar` pill. The Group Money shell with `leftAlignedTabBar` on draws
/// a small `HomeTabBar` at the leading edge on both, over a hidden system bar
/// on iOS 26. The native `TabView` builds and keeps every tab alive, so
/// two tabs opt out of that in ``tabContent(for:)``: Scan, whose camera is gated
/// on `selection` so it tears down, and Chat, which is not built until it is
/// first selected. The selected tab's push target is published to the router via
/// `activeTabStack`, since a tab is the active surface without being a sheet.
struct HomeTabView: View {

    @Environment(AppRouter.self) private var router
    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(Container.self) private var container
    @Environment(BetaFlags.self) private var betaFlags

    @State private var selection: HomeTab

    /// Whether the iOS 26 search tab is in front. `selection` keeps the tab it was opened from.
    @State private var isSearchSelected = false

    /// Whether Chat has been selected yet. Gates its first build; see
    /// ``tabContent(for:)``.
    @State private var hasOpenedChat: Bool

    /// The You tab's icon, once the profile has a picture. Owned here rather
    /// than by either bar, because both bars want the same download.
    @State private var profilePhoto = TabBarProfilePhoto()
    /// The Chats list's select mode. Held here because its capsules take the tab bar's place.
    @State private var chatSelection = ChatSelection()

    /// The bar tab to go back to when Scan or You is drawn over the shell,
    /// which happens only with the Group Money layout: it keeps them off the bar.
    @State private var lastBarTab: HomeTab

    init() {
        _selection = State(initialValue: HomeTab.initial)
        _lastBarTab = State(initialValue: HomeTab.initial)
        _hasOpenedChat = State(initialValue: HomeTab.initial == .chat)

        // Color the tab glyphs white in both states, as iOS 27 already does; the
        // outline-vs-filled glyph carries the selection. The iOS 26 tab bar
        // ignores UITabBar.unselectedItemTintColor, so drive it through a full
        // item appearance instead. A transparent background
        // keeps the system's Liquid Glass. No-op on the legacy pill path, which
        // draws its own buttons rather than a `UITabBar`.
        if #available(iOS 26, *) {
            let items = UITabBarItemAppearance()
            items.normal.iconColor = UIColor(Color.textMain)
            items.selected.iconColor = UIColor(Color.textMain)
            // Labels per node 10642:1325: 10pt Avenir Demi, colored like the glyph above.
            let titleFont = UIFont.default(size: 10, weight: .semibold)
            items.normal.titleTextAttributes = [.font: titleFont, .foregroundColor: UIColor(Color.textMain)]
            items.selected.titleTextAttributes = [.font: titleFont, .foregroundColor: UIColor(Color.textMain)]

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
    /// bill replaced the bottom bar).
    /// Sheets already cover the bar, so only in-tab pushes need handling here.
    @State private var cardExpansion = WalletCardExpansion()

    /// Set when the user comes back to a tab home from a screen pushed on it, so the update toast waits
    /// only for the navigation to settle rather than the full dwell.
    @State private var returnedToHome = false

    /// Today's four tabs, or Groups and Money behind `groupMoneyUI` for staff
    /// and developer-unlocked devices. Read live, so the toggle takes effect
    /// without a relaunch.
    private var layout: HomeTabLayout {
        HomeTabLayout(showsGroupMoney: betaFlags.showsGroupMoneyUI(isStaff: betaFlags.staffStanding(of: sessionContainer.session)))
    }

    /// Centred, or at the leading edge with the Group Money shell and
    /// `leftAlignedTabBar` both on. Read live, like ``layout``.
    private var barAlignment: HorizontalAlignment {
        layout.barAlignment(leftAligned: betaFlags.hasEnabled(.leftAlignedTabBar))
    }

    /// Whether the shell draws its own small bar at the leading edge, on every
    /// OS version. No public API moves the iOS 26 system bar off centre, so
    /// there the system bar is hidden and this bar drawn over the same
    /// `TabView`, which keeps the selected tab and every stack across a flip.
    private var drawsLeadingBar: Bool { barAlignment == .leading }

    /// The window's bottom safe area, outside anything the tab bar adds: what
    /// the small bar's inset is made up from.
    @State private var windowBottomInset: CGFloat = 0

    /// The signed-in account and the server's staff value for it, nil until
    /// fetched. Holds the account as well as the value, in case a switch
    /// between two accounts keeps this view.
    private struct StaffReading: Equatable {
        let userID: UserID
        let isStaff: Bool?
    }

    private var staffReading: StaffReading {
        StaffReading(
            userID: sessionContainer.session.userID,
            isStaff: sessionContainer.session.userFlags?.isStaff
        )
    }

    /// The bar tab in front: `selection`, or the one an off-bar tab covers.
    /// With today's layout every tab is on the bar, so this is `selection`.
    private var barSelection: HomeTab {
        if layout.isOnBar(selection) { return selection }
        return layout.isOnBar(lastBarTab) ? lastBarTab : layout.initialTab
    }

    /// The tab drawn over the shell because the bar has no slot for it: Scan
    /// or You with the Group Money layout. Nil with today's layout.
    private var offBarTab: HomeTab? {
        layout.isOnBar(selection) ? nil : selection
    }

    private var hasPushedScreen: Bool {
        guard !isSearchSelected else { return false }
        return selection.pushStack.map { !router[$0].isEmpty } ?? false
    }

    /// When the update toast may show on this view: the Chats or Wallet home, with nothing pushed or
    /// covering it.
    private var updateToastMoment: UpdateToastMoment? {
        guard selection == .chat || selection == .wallet,
              !isSearchSelected,
              !hasPushedScreen,
              !container.toasts.isCovered,
              !sessionContainer.session.isShowingBill,
              container.updateAvailability.isToastEligible
        else { return nil }
        return UpdateToastMoment(tab: selection, isReturn: returnedToHome)
    }

    private var isTabBarHidden: Bool {
        if isSearchSelected { return sessionContainer.session.isShowingBill }
        // The system bar fades out for select mode instead (see `nativeTabs`).
        if #unavailable(iOS 26), isChatSelecting { return true }
        return selection.hidesTabBar(
            isWalletCardExpanded: cardExpansion.isExpanded,
            isShowingBill: sessionContainer.session.isShowingBill,
            hasPushedScreen: hasPushedScreen
        )
    }

    /// Whether the Chat list is in select mode, where its capsules take the tab bar's place.
    private var isChatSelecting: Bool {
        selection == .chat && !isSearchSelected && chatSelection.isActive
    }

    /// Unread chats among the ones the Chat tab lists, surfaced as a badge on the tab.
    /// Reactive: reads the `@Observable` conversation store, so the badge updates as chats are read.
    private var chatBadgeCount: Int {
        sessionContainer.conversationController.unreadChatListCount
    }

    var body: some View {
        tabs
            // VoiceOver stays on Scan or You while it covers the shell.
            .accessibilityHidden(offBarTab != nil)
            .overlay { offBarLayer }
            // A gate flip moves Scan or You between the bar and the overlay in
            // one update. Animating that would keep the old copy on screen
            // beside the new one, both bound to the same router stack.
            .transaction(value: layout) { $0.animation = nil }
            .animation(.easeInOut(duration: 0.25), value: offBarTab)
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
            .onChange(of: router.requestedTab) { _, _ in selectRequestedTab() }
            .onChange(of: selection) { _, tab in
                router.activeTabStack = isSearchSelected ? nil : tab.pushStack
                if tab == .chat { hasOpenedChat = true }
                // Tracked whatever the layout, so turning Group Money on from
                // You (the only way to reach the toggle) closes back to the
                // tab the person came from rather than to Groups.
                if HomeTabLayout.groupMoney.isOnBar(tab) { lastBarTab = tab }
            }
            .onChange(of: isSearchSelected) { _, isSearching in
                router.activeTabStack = isSearching ? nil : selection.pushStack
            }
            // A gate flip to the shell takes the search tab away; don't leave it selected.
            .onChange(of: layout.hasSearchTab) { _, hasSearchTab in
                if !hasSearchTab { isSearchSelected = false }
            }
            .onDisappear { router.activeTabStack = nil }
            .onChange(of: router.presentedSheet != nil || sessionContainer.session.isShowingBill, initial: true) { _, covered in
                container.toasts.isCovered = covered
            }
            .onChange(of: hasPushedScreen) { wasPushed, isPushed in
                if wasPushed && !isPushed { returnedToHome = true }
            }
            .onChange(of: selection) { _, _ in returnedToHome = false }
            .task(id: updateToastMoment) {
                guard let moment = updateToastMoment else { return }
                try? await Task.sleep(for: moment.isReturn ? UpdatePolicy.returnSettle : UpdatePolicy.homeDwell)
                guard !Task.isCancelled else { return }
                returnedToHome = false
                container.updateAvailability.showToastIfEligible(on: container.toasts, timeout: UpdatePolicy.homeTimeout)
            }
            .onChange(of: sessionContainer.session.profile?.username, initial: true) { _, username in
                sessionContainer.chatArchive.setViewerUsername(username)
            }
            // Kept for the next cold start, whose first frame can come before
            // the server's value does.
            .onChange(of: staffReading, initial: true) { _, reading in
                betaFlags.recordStaffStanding(reading.isStaff, for: reading.userID)
            }
            // Fetched here rather than on the You tab, so its groups and their
            // avatars are in hand before the tab is first opened.
            .task(id: sessionContainer.session.profile?.username) {
                guard let username = sessionContainer.session.profile?.username else { return }
                let featuredGroups = sessionContainer.featuredGroups
                guard await featuredGroups.load(username: username) else { return }
                let avatars = sessionContainer.profileAvatars
                await withTaskGroup(of: Void.self) { group in
                    for conversation in featuredGroups.groups {
                        group.addTask { await avatars.load(.chat(conversation.id), picture: conversation.picture) }
                    }
                }
            }
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
    /// read back. Keying only on the loaded photo would show the no-photo glyph
    /// until it landed, on somebody who has a picture.
    private var profileSlot: ProfileTabSlot? {
        if let photo = profilePhoto.photo { return .photo(photo) }
        guard let picture = profilePicture, picture.thumbnailBlobID != nil else { return nil }
        return .pending(BlurHashCache.shared.image(for: picture.thumbnailBlurhash))
    }

    /// `profileSlot` in the form the iOS 26 bar takes its item images in.
    /// The Chat tab's glyphs with the unread count drawn in, or nil when
    /// nothing is unread; see ``TabBarBadgedIcon``.
    private var chatItemImages: TabBarProfilePhoto.ItemImages? {
        TabBarBadgedIcon.itemImages(for: .chat, count: chatBadgeCount, layout: layout)
    }

    private var profileItemImages: TabBarProfilePhoto.ItemImages? {
        guard let profileSlot else { return nil }

        switch profileSlot {
        case .photo:
            return profilePhoto.itemImages
        case .pending(let preview):
            return TabBarProfilePhoto.pendingItemImages(preview: preview)
        }
    }

    /// Holding the You tab opens the account switcher. The other tabs have no hold action.
    private func handleLongPress(on tab: HomeTab) {
        switch tab {
        case .tipCard:
            router.presentAccountSwitcher(gatedBy: betaFlags)
        case .scan, .wallet, .chat:
            break
        }
    }

    /// Brings the tab the router asked for forward and clears the request.
    private func selectRequestedTab() {
        guard let tab = router.requestedTab else { return }
        selection = tab
        isSearchSelected = false
        router.requestedTab = nil
    }

    /// Scan or You in front of the shell, when the Group Money layout leaves
    /// them off the bar and something asked for one: a deep link, a route onto
    /// the You stack, the Money avatar. Its close button goes back to the bar
    /// tab it covers. Draws nothing with today's layout.
    @ViewBuilder private var offBarLayer: some View {
        if let offBarTab {
            tabContent(for: offBarTab)
                .environment(\.homeTabClose, HomeTabClose { selection = barSelection })
                .toastHost(container.toasts)
                .background(Color.backgroundMain)
                .transition(.move(edge: .bottom))
        }
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
    /// bill-showing behavior matches the legacy pill. With the small bar at the
    /// leading edge the system bar stays hidden and ``nativeLeadingBar`` is
    /// drawn over the same `TabView`.
    @available(iOS 26, *)
    private var nativeTabs: some View {
        TabView(selection: nativeSelection) {
            ForEach(layout.barTabs) { tab in
                Tab(value: NativeTab.home(tab)) {
                    tabContent(for: tab)
                        .environment(\.shellBarBottomPadding, leadingBarSafeAreaPadding)
                        // Every tab stays alive, so only the selected one draws the toast. Raised over
                        // the small bar by what its safe area lacks, so it lands where it does over the
                        // system bar.
                        .toastHost(
                            container.toasts,
                            bottomPadding: 12 + leadingBarSafeAreaPadding,
                            isEnabled: !isSearchSelected && selection == tab
                        )
                        .toolbar(isTabBarHidden || drawsLeadingBar ? .hidden : .visible, for: .tabBar)
                        .environment(\.floatingTabBar, isTabBarHidden ? nil : FloatingTabBar(horizontalInset: Self.systemBarInset))
                } label: {
                    tabLabel(for: tab)
                        .accessibilityLabel(layout.title(for: tab))
                }
            }
            // The Group Money shell has no search. Without the search tab the
            // system draws the bar at its two items' width, centred. No public
            // API moves it from there, so with `leftAlignedTabBar` on it is
            // hidden and the small bar drawn in its place; see `nativeLeadingBar`.
            if layout.hasSearchTab {
                Tab(value: NativeTab.search, role: .search) {
                    NavigationStack {
                        ChatSearchScreen(chrome: .tab, navigate: openFromSearch, isActive: isSearchSelected)
                    }
                    .toastHost(container.toasts, isEnabled: isSearchSelected)
                    .toolbar(isTabBarHidden ? .hidden : .visible, for: .tabBar)
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
            }
        }
        // Selected-tab highlight over a lightly tinted glass bar — echoes the old
        // pill's white indicator on a translucent capsule.
        .tabViewSearchActivation(.searchTabSelection)
        .tint(Color.textMain)
        .toolbarBackground(Color.backgroundMain.opacity(0.5), for: .tabBar)
        // Gives each item both of its glyphs. The tab bar knows which item the
        // Liquid Glass pill is over mid-drag and renders that one selected, so
        // handing it the pair is what makes the icons fill under the finger
        // rather than when the drag commits — the binding does not change until
        // the finger lifts.
        .background(TabBarSelectedIcons(
            layout: layout,
            profileImages: profileItemImages,
            chatBadgeCount: chatBadgeCount,
            onLongPress: handleLongPress(on:)
        ))
        // Faded rather than hidden for select mode: a hidden bar takes its inset with it, and the
        // list's bottom scroll edge effect is drawn over that inset, so the blur behind the
        // capsules would go too.
        .background(TabBarFade(isFaded: isChatSelecting))
        .overlay { nativeLeadingBar }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { windowBottomInset = $0 }
    }

    /// The small bar over the hidden system bar. It hides on the same pushes,
    /// and fades for select mode as the system bar does, keeping its inset so
    /// the capsules take its slot.
    @available(iOS 26, *)
    private var nativeLeadingBar: some View {
        LeadingTabBarSlot(isVisible: drawsLeadingBar && !isTabBarHidden) {
            shellBar(alignment: .leading)
                .opacity(isChatSelecting ? 0 : 1)
                .allowsHitTesting(!isChatSelecting)
                .accessibilityHidden(isChatSelecting)
        }
        .animation(.easeInOut(duration: 0.2), value: isChatSelecting)
        .animation(.easeInOut(duration: 0.2), value: isTabBarHidden)
    }

    /// What the small bar adds to the bottom safe area on iOS 26, where it
    /// stands in for a system bar that would have added it: up to the bar's
    /// top, so scrolling content, the toast and the select-mode capsules sit
    /// where they do over the system bar. Each tab's root screen applies it
    /// through ``EnvironmentValues/shellBarBottomPadding``. Nothing while the
    /// bar is hidden, so a pushed screen keeps the full height.
    private var leadingBarSafeAreaPadding: CGFloat {
        guard drawsLeadingBar, !isTabBarHidden else { return 0 }
        return max(0, Self.leadingBarTop - windowBottomInset)
    }

    /// A tab in the iOS 26 bar: one of the shared tabs, or the search tab that sits apart from them.
    private enum NativeTab: Hashable {
        case home(HomeTab)
        case search
    }

    @available(iOS 26, *)
    private var nativeSelection: Binding<NativeTab> {
        Binding {
            isSearchSelected ? .search : .home(barSelection)
        } set: { tab in
            switch tab {
            case .home(let tab):
                isSearchSelected = false
                selection = tab
            case .search:
                isSearchSelected = true
            }
        }
    }

    /// Opens a search result on the Chat tab (Groups, with the Group Money
    /// layout), the stack its chats and currencies live on.
    private func openFromSearch(_ destination: AppRouter.Destination) {
        router.pushAny(destination, on: .tips)
        isSearchSelected = false
        selection = layout.searchResultTab
    }

    /// The unselected icon for a tab. The filled counterpart is handed to UIKit
    /// as the item's `selectedImage`, so the system owns the swap — choosing here
    /// instead would only ever be right once the selection had committed.
    ///
    /// This has to agree with what the probe writes. SwiftUI rewrites the item's
    /// image from this label whenever it rebuilds the bar, so a label that
    /// disagreed would take turns with the probe and flicker between the two.
    private func tabLabel(for tab: HomeTab) -> some View {
        Label {
            Text(layout.title(for: tab))
        } icon: {
            tabIcon(for: tab)
        }
    }

    @ViewBuilder private func tabIcon(for tab: HomeTab) -> some View {
        if tab == .tipCard, let photo = profileItemImages?.normal {
            Image(uiImage: photo).renderingMode(.original)
        } else if tab == .chat, let badged = chatItemImages?.normal {
            Image(uiImage: badged).renderingMode(.original)
        } else {
            Image(layout.iconName(for: tab, isSelected: false))
        }
    }

    /// The iOS 26 system bar's inset from the screen edge on a 402pt-wide
    /// iPhone: where its glass starts when the system lays it out from the
    /// leading edge, as it does beside a prominent tab or a bottom accessory.
    static let systemBarInset: CGFloat = 21

    /// The iOS 26 system bar's gap to the bottom of the screen, measured on a
    /// 402pt-wide iPhone: its glass ends at y=853 in an 874pt window.
    static let systemBarBottomInset: CGFloat = 21

    /// The small bar's top, measured up from the bottom of the screen: 83pt,
    /// where the system bar's inset ends too.
    static var leadingBarTop: CGFloat { systemBarBottomInset + HomeTabBar.height(.compact) }

    private static let pillBottomMargin: CGFloat = 8
    /// The legacy pill's margin from each side when centred: 318pt wide on a 402pt screen.
    static let legacyPillInset: CGFloat = 42

    /// The room the legacy pill occupies above the safe area. The pill is an
    /// overlay, so unlike the iOS 26 system bar it adds nothing to the safe
    /// area — a tab that scrolls under it has to inset for it itself. The small
    /// bar at the leading edge sits lower, so this clears it with room over.
    static var legacyPillClearance: CGFloat { HomeTabBar.height + pillBottomMargin }

    /// The shell's own bar: the small one for the leading edge, the legacy
    /// pill for the centre.
    private func shellBar(alignment: HorizontalAlignment) -> some View {
        HomeTabBar(
            selection: Binding { barSelection } set: {
                isSearchSelected = false
                selection = $0
            },
            layout: layout,
            size: HomeTabBar.Size(for: alignment),
            badgeCounts: [.chat: chatBadgeCount],
            profileSlot: profileSlot,
            onLongPress: handleLongPress(on:)
        )
    }

    /// iOS 18–25 fallback: the home-grown floating pill hovering over the tab
    /// content, sliding out when `isTabBarHidden`.
    private var legacyTabs: some View {
        ZStack(alignment: .bottom) {
            tabContent(for: barSelection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // The pill adds nothing to the safe area, so the toast clears it itself, and it draws
                // below the pill so it grows out from behind it.
                .toastHost(
                    container.toasts,
                    bottomPadding: isTabBarHidden ? 12 : 12 + Self.legacyPillClearance,
                    // An off-bar tab drawn over the shell hosts the toast itself.
                    isEnabled: offBarTab == nil
                )
                .transition(.opacity)
                .environment(\.floatingTabBar, isTabBarHidden ? nil : FloatingTabBar(horizontalInset: drawsLeadingBar ? Self.systemBarInset : Self.legacyPillInset))

            if drawsLeadingBar {
                LeadingTabBarSlot(isVisible: !isTabBarHidden) {
                    shellBar(alignment: .leading)
                }
            } else if !isTabBarHidden {
                shellBar(alignment: .center)
                    // Figma insets the pill ~42pt from each edge (318pt wide on the
                    // 402pt frame); a fixed margin keeps the floating look across
                    // device widths.
                    .padding(.horizontal, Self.legacyPillInset)
                    .padding(.bottom, Self.pillBottomMargin)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selection)
        .animation(.easeInOut(duration: 0.2), value: isTabBarHidden)
    }

    /// The content for a given tab. Two tabs are not simply built, because the
    /// native `TabView` builds and keeps all four alive: Scan is gated on
    /// `selection` so its camera tears down when the tab isn't active (an
    /// `onDisappear` alone wouldn't stop it), and Chat is held back until it is
    /// first selected.
    ///
    /// The legacy pill asks only for the selected tab, so both gates are no-ops
    /// there.
    @ViewBuilder private func tabContent(for tab: HomeTab) -> some View {
        switch tab {
        case .scan:
            if selection == .scan {
                ScanScreen()
            } else {
                Color.backgroundMain
            }
        case .wallet:
            WalletScreen()
                .environment(cardExpansion)
        case .chat:
            // Building the conversation list costs 300–550 ms, so when the app
            // launches on another tab it waits for the first selection rather
            // than janking that tab's first paint; `selection` alone answers the
            // frame Chat is tapped, so there is nothing to see in between.
            //
            // It stays built afterwards, unlike Scan. Scan is gated so it *does*
            // tear down; Chat holds state worth keeping — scroll position, a
            // half-filled profile form — that tearing down on every tab change
            // would discard.
            if selection == .chat || hasOpenedChat {
                ChatTab()
                    .environment(chatSelection)
            } else {
                Color.backgroundMain
            }
        case .tipCard:
            TipCardTab()
        }
    }
}

/// The small bar's slot: ``HomeTabView/systemBarInset`` in from the leading
/// edge and ``HomeTabView/systemBarBottomInset`` up from the bottom of the
/// screen, where the system bar's glass sits when the system lays it out from
/// the leading edge. Fills what it is offered and reaches past the bottom safe
/// area to the screen edge; only the bar takes touches. The bar slides out of
/// the slot when `isVisible` goes false.
struct LeadingTabBarSlot<Bar: View>: View {
    let isVisible: Bool
    let bar: Bar

    init(isVisible: Bool = true, @ViewBuilder bar: () -> Bar) {
        self.isVisible = isVisible
        self.bar = bar()
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if isVisible {
                bar
                    .padding(.leading, HomeTabView.systemBarInset)
                    .padding(.bottom, HomeTabView.systemBarBottomInset)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .ignoresSafeArea(edges: .bottom)
    }
}

extension EnvironmentValues {
    /// What a tab's root screen adds to its bottom safe area for the shell's
    /// small bar on iOS 26, which stands in for a hidden system bar that would
    /// have added it. 0 everywhere else. Safe area set outside a
    /// `NavigationStack` doesn't reach the screens inside it once the system
    /// bar is hidden, so each tab stack's root applies this itself with
    /// ``SwiftUI/View/shellBarSafeArea()``.
    @Entry var shellBarBottomPadding: CGFloat = 0
}

extension View {
    /// Adds ``EnvironmentValues/shellBarBottomPadding`` to the bottom safe
    /// area. Put it on a tab stack's root view, before its destinations, so
    /// pushed screens keep their own safe area.
    ///
    /// On iOS 26 the padding is a bar that draws nothing visible, so scrolling
    /// content softens under it across the screen's width, as it does under the
    /// system bar. On the root view rather than the stack, pushed screens get
    /// neither the inset nor the effect.
    func shellBarSafeArea() -> some View {
        modifier(ShellBarSafeArea())
    }
}

private struct ShellBarSafeArea: ViewModifier {
    @Environment(\.shellBarBottomPadding) private var padding

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .safeAreaBar(edge: .bottom, spacing: 0) {
                    // Not `Color.clear`: a bar of it gets no edge effect at all (checked on an
                    // iOS 27 simulator). A fill that draws, too faint to see, gets the soft one.
                    Color.black.opacity(0.001)
                        .frame(height: padding)
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                }
                // nil keeps the system's own style, so a flag-off tab is unchanged.
                .scrollEdgeEffectStyle(padding > 0 ? .soft : nil, for: .bottom)
        } else {
            content.safeAreaPadding(.bottom, padding)
        }
    }
}

/// A tab home the update toast can show on, and whether the user just came back to it.
private struct UpdateToastMoment: Equatable {
    let tab: HomeTab
    let isReturn: Bool
}

extension HomeTab {
    /// The router stack this tab pushes onto, published to `AppRouter` as the
    /// active push target. `nil` for tabs that only present sheets (Scan) or
    /// never push (Tip Card owns a local stack).
    ///
    /// Must agree with `AppRouter.Stack.isTabHosted`, which is what the router
    /// routes on; `AppRouterCrossStackTests` pins the two together.
    /// The tab that hosts `stack`, or nil for a stack no tab hosts.
    init?(hosting stack: AppRouter.Stack) {
        guard let tab = HomeTab.allCases.first(where: { $0.pushStack == stack }) else { return nil }
        self = tab
    }

    var pushStack: AppRouter.Stack? {
        switch self {
        case .wallet:  return .balance
        case .chat:    return .tips
        case .tipCard: return .you
        case .scan:    return nil
        }
    }

    /// Whether the tab bar hides while this tab is selected.
    ///
    /// An expanded card hides the bar only on the tab that owns it. The card
    /// stays open when a deep link or push brings another tab forward, so
    /// hiding on it everywhere left that tab with no bar and no way back.
    func hidesTabBar(
        isWalletCardExpanded: Bool,
        isShowingBill: Bool,
        hasPushedScreen: Bool
    ) -> Bool {
        if isShowingBill || hasPushedScreen { return true }
        switch self {
        case .wallet:                 return isWalletCardExpanded
        case .scan, .chat, .tipCard:  return false
        }
    }
}

// MARK: - Chat tab -

/// The Chat tab — the tip conversations surface. Mirrors `TipsSheetRoot` (the
/// `.tips` sheet) as embedded tab chrome: the same `NavigationStack` bound to
/// `router[.tips]`, minus the sheet's close button.
private struct ChatTab: View {

    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router[.tips]) {
            TipsScreen(isEmbedded: true)
                .shellBarSafeArea()
                .appRouterDestinations()
        }
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

    /// Set when You is drawn over the shell rather than shown as a tab.
    @Environment(\.homeTabClose) private var close

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router[.you]) {
            YouScreen()
                .toolbar {
                    if let close {
                        ToolbarItem(placement: .topBarLeading) {
                            CloseButton(action: close.action)
                        }
                    }
                }
                .shellBarSafeArea()
                .appRouterDestinations()
        }
    }
}

/// Hands each tab bar item its selected glyph, which SwiftUI's `Tab` has no API
/// for, and listens for a long press on the bar, which `Tab` has no API for
/// either.
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
    /// Which tabs the bar holds and which glyph each wears.
    let layout: HomeTabLayout

    /// The You tab's photo, in place of its glyph. Passed by value so the
    /// enclosing body observes it landing and this representable is updated.
    let profileImages: TabBarProfilePhoto.ItemImages?

    /// Unread chats, drawn into the Chat glyph in place of the system badge,
    /// which the glass lens draws beneath the glyph mid-drag.
    let chatBadgeCount: Int

    /// Called with the tab whose item was held.
    let onLongPress: (HomeTab) -> Void

    func makeUIViewController(context: Context) -> Probe {
        Probe(layout: layout, profileImages: profileImages, chatBadgeCount: chatBadgeCount, onLongPress: onLongPress)
    }

    func updateUIViewController(_ probe: Probe, context: Context) {
        probe.layout = layout
        probe.profileImages = profileImages
        probe.chatBadgeCount = chatBadgeCount
        probe.onLongPress = onLongPress
        probe.apply()
    }

    final class Probe: UIViewController, UIGestureRecognizerDelegate {
        var layout: HomeTabLayout
        var profileImages: TabBarProfilePhoto.ItemImages?
        var chatBadgeCount: Int
        var onLongPress: (HomeTab) -> Void

        init(
            layout: HomeTabLayout,
            profileImages: TabBarProfilePhoto.ItemImages?,
            chatBadgeCount: Int,
            onLongPress: @escaping (HomeTab) -> Void
        ) {
            self.layout = layout
            self.profileImages = profileImages
            self.chatBadgeCount = chatBadgeCount
            self.onLongPress = onLongPress
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
        /// where this controller is first added, and still hold the other
        /// layout's on the pass after a gate flip.
        func apply() {
            // The search tab, when there is one, is the last item and keeps its system glyph.
            guard let bar = resolvedTabBar,
                  let items = bar.items,
                  let tabs = layout.barTabs(forItemCount: items.count)
            else {
                scheduleRetry()
                return
            }
            installLongPress(on: bar)

            for (item, tab) in zip(items, tabs) {
                if tab == .tipCard, let profileImages {
                    // Already rendered at the dimmed and full opacities the bar
                    // would otherwise get by tinting a template glyph.
                    item.image = profileImages.normal
                    item.selectedImage = profileImages.selected
                    continue
                }
                if tab == .chat {
                    // The drawn-in count is invisible to VoiceOver, so the item
                    // carries it the way the system badge did.
                    item.accessibilityValue = chatBadgeCount > 0 ? "\(chatBadgeCount) unread" : nil
                    if let badged = TabBarBadgedIcon.itemImages(for: .chat, count: chatBadgeCount, layout: layout) {
                        item.image = badged.normal
                        item.selectedImage = badged.selected
                        continue
                    }
                }

                item.image = UIImage(named: layout.iconName(for: tab, isSelected: false))?
                    .withRenderingMode(.alwaysTemplate)
                item.selectedImage = UIImage(named: layout.iconName(for: tab, isSelected: true))?
                    .withRenderingMode(.alwaysTemplate)
            }
        }

        // MARK: - Long press -

        /// The bar the recognizer is on, so a rebuilt bar gets its own and the
        /// same bar is never given two.
        private weak var longPressTarget: UITabBar?

        private func installLongPress(on bar: UITabBar) {
            guard longPressTarget !== bar else { return }
            let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
            // Without a delegate the bar's own `_UIContinuousSelectionGestureRecognizer`
            // — the one that tracks a finger sliding across the items — wins the
            // conflict and this one never begins.
            recognizer.delegate = self
            // Let the bar keep its touches: the press still selects the held tab
            // on release, the same as the legacy pill.
            recognizer.cancelsTouchesInView = false
            bar.addGestureRecognizer(recognizer)
            longPressTarget = bar
        }

        @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, let bar = recognizer.view as? UITabBar else { return }
            guard let tab = TabBarItemLocator.tab(at: recognizer.location(in: bar), in: bar, tabs: layout.barTabs) else { return }
            onLongPress(tab)
        }

        /// Runs alongside the bar's own recognizers rather than instead of them,
        /// so holding an item still selects it and a slide across the bar still
        /// tracks.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }

        // MARK: - Retry -

        private var hasRetryScheduled = false

        private func scheduleRetry() {
            guard !hasRetryScheduled else { return }
            hasRetryScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.hasRetryScheduled = false
                self?.apply()
            }
        }
    }
}

/// Fades the system tab bar out and back in, with the animation of the SwiftUI update that changed
/// `isFaded`. The bar keeps its place and its inset; it only stops drawing and taking touches.
@available(iOS 26, *)
private struct TabBarFade: UIViewControllerRepresentable {
    let isFaded: Bool

    func makeUIViewController(context: Context) -> Probe {
        Probe()
    }

    /// Re-applies on every update, not only on a change: SwiftUI can rebuild the bar mid-fade.
    func updateUIViewController(_ probe: Probe, context: Context) {
        guard probe.isFaded != isFaded else {
            probe.apply()
            return
        }
        probe.isFaded = isFaded
        context.animate { probe.apply() }
    }

    final class Probe: UIViewController {
        var isFaded = false

        func apply() {
            guard let bar = resolvedTabBar else { return }
            bar.alpha = isFaded ? 0 : 1
            // A view mid-fade still takes touches, and the bar sits above the SwiftUI content.
            bar.isUserInteractionEnabled = !isFaded
            bar.accessibilityElementsHidden = isFaded
        }
    }
}

private extension UIViewController {

    /// This controller is attached alongside the `TabView` rather than inside
    /// a tab, so `tabBarController` is nil — the bar has to be found from the
    /// window instead.
    var resolvedTabBar: UITabBar? {
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
