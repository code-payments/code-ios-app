//
//  HomeTabView.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// The v2 tab-bar root, shown post-login when `BetaFlags.newUI` is enabled (in
/// place of the scanner-first `ScanScreen`). Hosts the four tabs behind a
/// floating pill `HomeTabBar`, launches on Wallet, and owns the app-level
/// `router.rootSheet` host so `router.present(_:)` works from any tab.
///
/// Only the selected tab is mounted (a plain `switch`, not a `TabView` — the
/// deployment target predates the tab-bar-hiding APIs): switching tabs unmounts
/// the previous one, so the Scan camera stops via its own `onDisappear`. The
/// selected tab's push target is published to the router via `activeTabStack`,
/// since a tab is the active surface without being a sheet.
struct HomeTabView: View {

    @Environment(AppRouter.self) private var router

    @State private var selection: HomeTab = .initial

    var body: some View {
        ZStack(alignment: .bottom) {
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)

            HomeTabBar(selection: $selection)
                // Figma insets the pill ~42pt from each edge (318pt wide on the
                // 402pt frame); a fixed margin keeps the floating look across
                // device widths.
                .padding(.horizontal, 42)
                .padding(.bottom, 8)
        }
        .background(Color.backgroundMain)
        .animation(.easeInOut(duration: 0.2), value: selection)
        // The app-level sheet host lives here in v2 (ScanScreen suppresses its
        // own copy when embedded) so `router.present(_:)` works from any tab.
        .modifier(RootSheetHostModifier(enabled: true))
        .onAppear { router.activeTabStack = selection.pushStack }
        .onChange(of: selection) { _, tab in router.activeTabStack = tab.pushStack }
        .onDisappear { router.activeTabStack = nil }
    }

    @ViewBuilder private var tabContent: some View {
        switch selection {
        case .scan:
            ScanScreen(isEmbedded: true)
        case .wallet:
            WalletScreen()
        case .chat:
            ChatTab()
        case .tipCard:
            TipCardTab(onSetUp: { selection = .chat })
        }
    }
}

private extension HomeTab {
    /// The router stack this tab pushes onto, published to `AppRouter` as the
    /// active push target. `nil` for tabs that only present sheets (Scan) or
    /// never push (Tip Card owns a local stack).
    var pushStack: AppRouter.Stack? {
        switch self {
        case .wallet:         return .balance
        case .chat:           return .tips
        case .scan, .tipCard: return nil
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
            TipsScreen()
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

    @Environment(SessionContainer.self) private var sessionContainer

    let onSetUp: () -> Void

    var body: some View {
        NavigationStack {
            if sessionContainer.session.profile?.isTippable == true {
                TipcardScreen()
            } else {
                TipCardSetupPrompt(onSetUp: onSetUp)
            }
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
