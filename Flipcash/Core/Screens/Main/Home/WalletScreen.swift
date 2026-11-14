//
//  WalletScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// The Wallet tab: the big balance header, per-token bill cards in a collapsing
/// ``TokenCardStack``, and an add-money affordance. Owns its own
/// `NavigationStack` bound to `router[.balance]`, so the push destinations
/// (currency info, transaction history) work unchanged.
struct WalletScreen: View {

    @Environment(SessionContainer.self) private var sessionContainer

    var body: some View {
        WalletScreenContent(sessionContainer: sessionContainer)
    }
}

private struct WalletScreenContent: View {

    @Environment(AppRouter.self) private var router
    @Environment(RatesController.self) private var ratesController
    @Environment(HistoryController.self) private var historyController
    /// Reported so the tab bar hides while a card is open — the expansion is an
    /// overlay, so the usual push-based rule does not see it.
    @Environment(WalletCardExpansion.self) private var cardExpansion
    @Environment(BetaFlags.self) private var betaFlags
    @Environment(SessionContainer.self) private var sessionContainer

    let session: Session

    /// Today's wallet, or the Money screen behind `groupMoneyUI` (node 13729:744).
    private var layout: WalletLayout {
        WalletLayout(showsGroupMoney: betaFlags.showsGroupMoneyUI(isStaff: betaFlags.staffStanding(of: session)))
    }
    @State private var cards: [TokenCardData] = []
    @State private var total: ExchangedFiat
    @State private var appreciation: (amount: FiatAmount, isPositive: Bool)
    @State private var hasAddedMoney: Bool
    /// The unified recent-activity preview (newest first).
    @State private var recentActivities: [Activity]

    /// The card the wallet is showing arrive with a deposit — it enters rather
    /// than simply being there. `nil` when nothing is arriving.
    @State private var arrivingMint: PublicKey?
    /// How far that arrival has run: 0 is off-stage, 1 is settled.
    @State private var arrivalProgress: CGFloat = 1

    /// The opened card's transition: the deck clearing around it, and the page
    /// that comes in behind it.
    private var deck = WalletCardDeck()
    /// Size of the wallet's container, used to push the lower cards off-screen
    /// and to size the detail panel below the open card.
    @State private var containerSize: CGSize = .zero

    /// Safe-area insets: the wallet's container excludes them, so they are added
    /// back when sizing the panel against the full screen.
    @State private var safeArea: EdgeInsets = .init()

    private var safeAreaTop: CGFloat { safeArea.top }

    /// The top inset outside the navigation stack: the status bar's alone, where `safeArea`
    /// also counts Money's bar.
    @State private var statusBarInset: CGFloat = 0

    /// Geometry taken from the currency info spec (Figma 9121:14267), which
    /// places the card at y=134.5 with the 44pt chrome at y=66, and starts the
    /// action tiles 22pt below the card. The panel supplies 8pt of its own top
    /// padding before those tiles, so it starts 14pt under the card.
    private static let openCardTopInset: CGFloat = 72
    private static let openCardHeight: CGFloat = 224
    private static let cardToPanelGap: CGFloat = 14
    /// Chrome sits 12pt below the status bar, per the same frame.
    private static let chromeTopPadding: CGFloat = 2

    /// Matched-transition namespace shared with the pushed currency-info screen.
    @Namespace private var cardNamespace

    /// Rows of recent activity read for either layout, which each show their own share of them
    /// (the rest lives on the full history).
    private static let recentFetchCount = max(
        WalletLayout.standard.recentActivityLimit,
        WalletLayout.money.recentActivityLimit
    )

    /// The recent activity this layout lists.
    private var listedActivities: [Activity] {
        Array(recentActivities.prefix(layout.recentActivityLimit))
    }

    /// The scroll view's visible height, between the bar and the tab bar, which Money's content
    /// fills at the least so Recent Activity runs to the bottom of the screen.
    @State private var scrollViewportHeight: CGFloat = 0

    /// Where the balance sits, measured from the top of the screen rather than
    /// from the top of this scroll view — 20pt of list inset plus the spec's
    /// 96pt, which is how far down Android puts it. Android draws its list edge
    /// to edge and insets the content, so its 96 starts under the status bar;
    /// laying out below the safe area here and adding the same 96 puts the
    /// balance a whole status bar lower than it sits on Android.
    private static let headerTopFromScreenEdge: CGFloat = 116

    private var headerTopPadding: CGFloat {
        max(0, Self.headerTopFromScreenEdge - safeArea.top)
    }

    /// Where Money's balance sits below the status bar: the 20pt and 44pt of the title row it
    /// drew under the status bar before that row moved into the bar, then the spec's 64pt.
    private static let moneyBalanceTopFromStatusBar: CGFloat = 20 + 44 + 64

    /// The bar is not the title row's 44pt on every iOS version (54pt on iOS 27), so the
    /// balance pads from the height the bar actually takes.
    private var moneyBalanceTopPadding: CGFloat {
        max(0, statusBarInset + Self.moneyBalanceTopFromStatusBar - safeArea.top)
    }
    /// How far below the status bar content returns to full strength.
    private static let topFadeLength: CGFloat = 20

    /// The gap the content keeps between its last tile and the tab bar.
    private static let tabBarGap: CGFloat = 40

    /// Bottom inset for the scrolling content. The iOS 26 tab bar sits in the
    /// safe area, so the gap is the whole inset there; the legacy pill floats
    /// over the content and has to be cleared on top of it.
    private var bottomContentInset: CGFloat {
        if #available(iOS 26, *) {
            return Self.tabBarGap
        }
        return Self.tabBarGap + HomeTabView.legacyPillClearance
    }

    init(sessionContainer: SessionContainer) {
        self.session = sessionContainer.session
        let rate = sessionContainer.ratesController.rateForBalanceCurrency()
        // Seed synchronously so the first render shows real balances, not an
        // empty-state flash.
        let seed = Self.snapshot(session: sessionContainer.session, rate: rate)
        _cards = State(initialValue: seed.cards)
        // A released deposit can land before this view exists — the legacy tab
        // path builds the wallet when the tab is selected, which is the moment
        // "Put in Wallet" asks for. Seeded at the pre-deposit figures so the
        // rise still has somewhere to start.
        let landing = sessionContainer.session.walletDeposit.releasedLanding
        _total = State(initialValue: landing?.previousTotal ?? seed.total)
        _arrivingMint = State(initialValue: landing?.isNewToken == true ? landing?.mint : nil)
        _arrivalProgress = State(initialValue: landing?.isNewToken == true ? 0 : 1)
        _appreciation = State(initialValue: seed.appreciation)
        _hasAddedMoney = State(initialValue: sessionContainer.session.hasEverAddedMoney())
        _recentActivities = State(initialValue: sessionContainer.session.recentActivities(limit: Self.recentFetchCount))
    }

    private var rate: Rate { ratesController.rateForBalanceCurrency() }

    private var addMoneyRowState: AddMoneyRowState {
        AddMoneyRowState(
            hasAddedMoney: hasAddedMoney,
            historySyncState: historyController.syncState,
            hasStoredActivity: !recentActivities.isEmpty
        )
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router[.balance]) {
            Background(color: .backgroundMain) {
                walletContent
            }
            .walletCardPage(deck) { closeCard(resumingFrom: $0) }
            .onChange(of: router.requestedCardMint) { _, _ in openRequestedCard() }
            // A flow launched from the expanded card (Convert, Get) finished and
            // asked to land back on the wallet — close the card overlay.
            .onChange(of: router.requestedCardDismiss) { _, _ in
                closeCard()
            }
            // Keyed on the deposit itself, so an arrival plays whether the
            // wallet was already alive behind the bill (iOS 26 keeps every tab
            // mounted) or is built on arrival.
            .task(id: session.walletDeposit.releasedLanding?.mint) { await playDeposit() }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { containerSize = $0 }
            .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { safeArea = $0 }
            // No top bar on today's wallet root (per Figma) — the balance header
            // sits directly under the status bar. Money puts its title and avatar
            // in the bar, where Groups puts its title and Add, so switching tabs
            // leaves them in place. Pushed destinations restore their own nav bar.
            .toolbar(showsMoneyBar ? .visible : .hidden, for: .navigationBar)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                if showsMoneyBar {
                    moneyBarItems
                }
            }
            .appRouterDestinations()
            .onAppear {
                historyController.sync()
                // Tabs are built on first selection, so a deep link that arrives
                // while another tab is showing (or at cold start) parks its mint
                // before this view exists to observe the change.
                openRequestedCard()
            }
            .onChange(of: session.balances) { _, _ in
                refresh()
                // The "add money" milestone is met by a balance as well as by
                // history, so a balance that moved can settle it on its own —
                // without this it would wait on an activity row that may never
                // come.
                reloadHistoryState()
                // A balance that moved has an activity row on its way, so pull
                // it now. `onAppear` cannot be the only sync: the tab stays
                // alive behind sheets and behind the other tabs, so it fires
                // once per launch and never again after a deposit lands.
                historyController.sync()
            }
            .onChange(of: rate) { _, _ in refresh() }
            // Activities land in the DB independently of a balance change (e.g.
            // a synced history page), and both the recent preview and the
            // add-money milestone are derived from them — so reload both on
            // any DB change rather than only when a balance moves.
            .onReceive(NotificationCenter.default.publisher(for: .databaseDidChange)) { _ in
                reloadHistoryState()
            }
            // Popping back to the wallet restores the deck.
            // Deliberately not watching the stack depth to decide whether the
            // card is still open. The opened card is an overlay, not a stack
            // entry, so an empty stack is its *normal* state — pushing the full
            // transaction history and popping back returns the depth to zero,
            // which a depth watcher reads as "back at the wallet" and closes the
            // card out from under the screen the user was returning to.
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { statusBarInset = $0 }
        .environment(\.walletCardNamespace, cardNamespace)
    }

    /// Opens a token: the deck reorganises around the tapped card, which stays
    /// on screen while the detail panel rises beneath it.
    private func openCard(_ item: TokenCardData, currentTop: CGFloat) {
        Analytics.tokenInfoOpened(from: .openedFromWallet, mint: item.mint)
        deck.open(item.mint, currentTop: currentTop, safeAreaTop: safeArea.top) {
            cardExpansion.isExpanded = true
        }
    }

    /// Back + share for the opened card, standing in for the navigation bar the
    /// wallet root hides.
    private func openCardChrome(mint: PublicKey) -> some View {
        HStack {
            Button { closeCard() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.textMain)
                    .frame(width: 44, height: 44)
                    // Without this the button only takes taps on the glyph
                    // itself, leaving most of the 44pt target dead.
                    .contentShape(Circle())
                    .modifier(WalletCircleGlass())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("wallet-open-card-back")

            Spacer(minLength: 0)

            if mint != .usdf {
                ShareLink(item: URL(string: "https://app.flipcash.com/token/\(mint.base58)")!) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.textMain)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                        .modifier(WalletCircleGlass())
                }
                .simultaneousGesture(TapGesture().onEnded {
                    Analytics.buttonTapped(name: .shareTokenInfo)
                })
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, Self.chromeTopPadding)
        .transition(.opacity)
    }

    /// Opens the card the router asked for, if any, and clears the request.
    private func openRequestedCard() {
        guard let mint = router.requestedCardMint else { return }
        openCardImmediately(mint)
        router.requestedCardMint = nil
    }

    /// Arrives in the opened state without the travel — for a deep link, where
    /// there is no tap to have come from and the card may not even be on screen
    /// to start from.
    private func openCardImmediately(_ mint: PublicKey) {
        Analytics.tokenInfoOpened(from: .openedFromDeeplink, mint: mint)
        deck.openImmediately(mint) { cardExpansion.isExpanded = true }
    }

    /// Closes a token: the reverse of opening.
    private func closeCard(resumingFrom pullOffset: CGFloat = 0) {
        deck.close(
            resumingFrom: pullOffset,
            restoresContentAtOnce: layout.restoresContentWhenCardCloses
        ) {
            cardExpansion.isExpanded = false
        }
    }

    // MARK: - Content

    private var walletContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if layout == .money {
                moneyContent
            } else {
                standardContent
            }
        }
        // Gated on the page being up rather than on `expandingMint`, which is
        // held until the closing spring is fully removed — a good deal later
        // than it looks finished. Tying the lock to it left the wallet inert for
        // that tail: a swipe found a disabled scroll view and fell through to
        // the card underneath as a tap.
        .scrollDisabled(deck.pageIsBuilt)
        // The container is already the part between the bar and the tab bar.
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.containerSize.height
        } action: { _, height in
            scrollViewportHeight = max(0, height)
        }
        // The app-wide soft edge effect is drawn from a bar's own background,
        // and today's wallet hides its navigation bar, so it covers the bottom
        // (tab bar) but not the top — what scrolls up into the status bar has
        // to be faded by hand. Money's bar draws its own.
        .overlay(alignment: .top) {
            if layout == .standard {
                LinearGradient(
                    colors: [Color.backgroundMain, Color.backgroundMain.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: safeArea.top + Self.topFadeLength)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Money layout

    /// The Money screen: title and avatar, the balance, the currencies held,
    /// Add Money and Withdraw, then recent activity. No card stack, so a token
    /// opens from the currencies list, or straight to its page from a deep link.
    private var moneyContent: some View {
        VStack(spacing: 0) {
            ForEach(layout.sections, id: \.self) { section in
                moneySection(section)
            }

            // Bottom inset so the last row clears the tab bar.
            Color.clear.frame(height: bottomContentInset)
        }
        // At least the screen's height, so Recent Activity can take the rest of it.
        .frame(minHeight: scrollViewportHeight, alignment: .top)
        .padding(.horizontal, 20)
        .opacity(deck.deckOpacity)
        .task(id: session.profile?.profilePicture?.thumbnailBlobID) {
            await sessionContainer.profileAvatars.load(userID: session.userID, picture: session.profile?.profilePicture)
        }
    }

    @ViewBuilder
    private func moneySection(_ section: WalletSection) -> some View {
        switch section {
        case .title:
            // Drawn in the navigation bar; see `moneyBarItems`.
            EmptyView()
        case .balance:
            BalanceHeaderButton(balance: total)
                .frame(height: 60)
                .padding(.top, moneyBalanceTopPadding)
        case .currencyCount:
            currencyCountButton
                .padding(.top, 4)
        case .actions:
            moneyActions
                .padding(.top, 40)
        case .recentActivity:
            moneyRecentActivity
                .padding(.top, 44)
                // Takes whatever height the blocks above leave.
                .frame(maxHeight: .infinity, alignment: .top)
        case .balanceHeader, .appreciation, .addMoneyRow, .tokenCards, .tiles:
            EmptyView()
        }
    }

    /// Money's Recent Activity: its rows, or once history has been looked for and holds none, a
    /// message centred in the space the section fills.
    private var moneyRecentActivity: some View {
        let activities = listedActivities
        return VStack(spacing: 0) {
            RecentActivitySection(activities: activities, title: MoneyHeaderContent.recentActivityTitle, rowStyle: .money) {
                router.push(.activity)
            }
            if activities.isEmpty && !addMoneyRowState.isAwaitingHistory {
                Text("No activity yet")
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// Money's bar, while no currency page covers the screen: the page draws its own chrome over
    /// the wallet, and a bar would sit on top of it and push it down.
    private var showsMoneyBar: Bool {
        layout == .money && !deck.pageIsBuilt
    }

    /// The title where Groups draws its own, and the avatar in the slot Groups gives Add.
    @ToolbarContentBuilder private var moneyBarItems: some ToolbarContent {
        ShellTabTitle(title: MoneyHeaderContent.title, accessibilityIdentifier: "money-title")
        // The photo is the control, so no glass behind it.
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarTrailing) { moneyProfileButton }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarTrailing) { moneyProfileButton }
        }
    }

    private var moneyProfileButton: some View {
        Button {
            MoneyAction.profile.perform(on: router)
        } label: {
            ContactAvatarView(
                id: session.userID.uuidString,
                displayName: session.profile?.displayName ?? "",
                imageData: sessionContainer.profileAvatars.data(for: session.userID),
                blurhash: session.profile?.profilePicture?.thumbnailBlurhash,
                size: 44
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("You")
        .accessibilityIdentifier("money-profile-button")
    }

    private var currencyCountButton: some View {
        Button {
            MoneyAction.currencies.perform(on: router)
        } label: {
            HStack(spacing: 4) {
                Text(MoneyHeaderContent.currencyCountText(cards.count))
                Image(systemName: "chevron.right")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 7, height: 10)
            }
            .font(.appTextSmall)
            .foregroundStyle(Color.textSecondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("money-currencies-button")
    }

    private var moneyActions: some View {
        HStack(spacing: 12) {
            CodeButton(style: .filled, title: MoneyHeaderContent.addMoneyTitle) {
                MoneyAction.addMoney.perform(on: router)
            }
            .accessibilityIdentifier("money-add-money-button")
            CodeButton(style: .filledSecondary, title: MoneyHeaderContent.withdrawTitle) {
                MoneyAction.withdraw.perform(on: router)
            }
            .accessibilityIdentifier("money-withdraw-button")
        }
    }

    // MARK: - Today's layout

    private var standardContent: some View {
        VStack(spacing: 0) {
            // Header + Add Money row scroll off first; the card stack then reaches the
            // top and collapses into its back card. The stack measures the
            // scroll itself (via `.visualEffect`), so no height plumbing here.
            VStack(spacing: 0) {
                header
                    // Figma (8966:1578) drops the balance well down the screen —
                    // most of the extra space sits above it, less below.
                    .padding(.top, headerTopPadding)
                    .padding(.bottom, 44)

                if addMoneyRowState.isVisible {
                    addMoneyRow
                        .padding(.bottom, 20)
                }
            }
            // The stack is deliberately outside the fade: its cards carry
            // their own, driven by the same progress, so the opened one can
            // stay solid while the rest of the deck goes.
            .opacity(deck.deckOpacity)

            if !cards.isEmpty {
                TokenCardStack(
                    items: cards,
                    namespace: cardNamespace,
                    expandingMint: deck.expandingMint,
                    expansionProgress: deck.expansionProgress,
                    containerHeight: containerSize.height,
                    hiddenMint: deck.hiddenMint,
                    openTopInset: WalletCardGeometry.openCardTopInset,
                    openExtraOffset: deck.releasedPullOffset,
                    arrivingMint: arrivingMint,
                    arrivalProgress: arrivalProgress,
                    onCardTap: openCard
                )
            }

            Group {
                if !recentActivities.isEmpty {
                    recentActivitySection
                }

                // Returning users (already funded) get the tile shortcuts
                // below the activity; new users get the Add Money row
                // above instead.
                if hasAddedMoney {
                    walletTiles
                        .padding(.top, 24)
                }
            }
            .opacity(deck.deckOpacity)

            // Bottom inset so the last tile clears the tab bar.
            Color.clear.frame(height: bottomContentInset)
        }
        .padding(.horizontal, 20)
    }

    private var header: some View {
        VStack(spacing: 4) {
            BalanceHeaderButton(balance: total)
                .frame(height: 60)
            ValueAppreciation(amount: appreciation.amount, isPositive: appreciation.isPositive, style: .pill)
        }
    }

    private var walletTiles: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                walletTile(icon: .asset(.coinsAdd), title: "Create Your Own Currency", identifier: "wallet-tile-create-currency") {
                    router.push(.currencyCreationSummary)
                }
                walletTile(icon: .symbol("globe"), title: "Currency Leaderboard", identifier: "wallet-tile-discover-currencies") {
                    router.push(.discoverCurrencies)
                }
            }
            HStack(spacing: 12) {
                // `.deposit`/`.withdraw` are the app's canonical design-system
                // glyphs for these actions — a matched arrow-to-baseline pair,
                // not SF Symbols.
                walletTile(icon: .asset(.deposit), title: "Add Dollars", identifier: "wallet-tile-add-money") {
                    router.presentAddMoney(.general, source: .balance)
                }
                // A nil mint opens the currency picker (all balances).
                walletTile(icon: .asset(.withdraw), title: "Withdraw Dollars", identifier: "wallet-tile-withdraw-money") {
                    router.push(.withdrawCurrency(nil))
                }
            }
        }
    }

    /// A wallet tile's leading glyph: an SF Symbol, or a bundled design-system
    /// asset for marks SF Symbols don't cover (the two-coin "create currency" one).
    private enum TileGlyph {
        case symbol(String)
        case asset(Asset)
    }

    /// A tile-style entry point: icon top-leading, label pinned bottom-leading,
    /// inside a translucent rounded card. They tile two-up per row.
    ///
    /// `identifier` is what tests target, so they do not depend on the label.
    private func walletTile(icon: TileGlyph, title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                tileGlyph(icon)
                    .foregroundStyle(Color.textMain)
                Spacer(minLength: 24)
                Text(title)
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 96)
            .padding(16)
            .background(Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: Metrics.buttonRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    /// Renders a `TileGlyph` at a consistent ~24pt: SF Symbols sized by font,
    /// asset glyphs scaled to fit and tinted via the enclosing `foregroundStyle`.
    @ViewBuilder
    private func tileGlyph(_ glyph: TileGlyph) -> some View {
        switch glyph {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 22, weight: .regular))
        case .asset(let asset):
            Image.asset(asset)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
        }
    }

    private var recentActivitySection: some View {
        // The header opens the full cross-token history here; currency info
        // passes its own per-token destination.
        RecentActivitySection(activities: listedActivities) {
            router.push(.activity)
        }
        .padding(.top, 24)
    }

    private var addMoneyRow: some View {
        Button {
            router.presentAddMoney(.general, source: .balance)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "plus.circle")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(Color.textSecondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Add Money")
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                    Text("Add money to your account")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(Color.backgroundRow)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.buttonRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("wallet-add-money-row")
    }

    // MARK: - Deposit

    /// Whether a released deposit is still on its way to being shown.
    private var isLandingDeposit: Bool { session.walletDeposit.releasedLanding != nil }

    /// Shows a grabbed deposit arriving: the wallet rewinds to the figures it
    /// was last seen with, then runs the balance up and brings in a card for a
    /// token it had none for.
    private func playDeposit() async {
        guard let landing = session.walletDeposit.releasedLanding else { return }
        let isNewToken = landing.isNewToken

        // The balances already carry the deposit, so this is a step backwards —
        // taken in one un-animated frame, under the bill that is still covering
        // the wallet.
        var rewind = Transaction()
        rewind.disablesAnimations = true
        withTransaction(rewind) {
            total = landing.previousTotal
            arrivingMint = isNewToken ? landing.mint : nil
            arrivalProgress = isNewToken ? 0 : 1
        }

        // The bill is sliding down and its sheet coming off as this starts;
        // running the rise underneath them spends it where it cannot be seen.
        try? await Task.delay(milliseconds: Self.depositRevealDelay)
        guard !Task.isCancelled else { return }

        let snapshot = Self.snapshot(session: session, rate: rate)
        withAnimation(.smooth(duration: Self.depositArrivalDuration), completionCriteria: .removed) {
            cards = snapshot.cards
            total = snapshot.total
            appreciation = snapshot.appreciation
            arrivalProgress = 1
        } completion: {
            arrivingMint = nil
            // Held until here rather than cleared up front: while a landing is
            // pending it is also what holds `refresh()` off the figures the
            // animation is moving.
            session.walletDeposit.consume()
            // Picks up anything that moved while the figures were held.
            refresh()
        }
    }

    /// How long the wallet waits for the bill and its sheet to clear before
    /// playing the arrival.
    private static let depositRevealDelay = 450
    /// How long the arriving card takes to rise into its slot. The balance rolls
    /// on `BalanceHeaderButton`'s own animation, not this one.
    private static let depositArrivalDuration: TimeInterval = 0.9

    // MARK: - Data

    private func refresh() {
        // A landing owns the figures until it has played them; refreshing here
        // would put the wallet back to the post-deposit total it is rewound
        // from, cutting to the answer the rise is on its way to.
        guard !isLandingDeposit else { return }
        let snapshot = Self.snapshot(session: session, rate: rate)
        withAnimation(.default) {
            cards = snapshot.cards
            total = snapshot.total
            appreciation = snapshot.appreciation
        }
    }

    /// Re-reads the history-derived state: the recent-activity preview and the
    /// add-money milestone. Both come from the activity table, which a history
    /// sync writes without touching balances — so they
    /// cannot ride on ``refresh()``'s balance trigger, and a deposit's activity
    /// row routinely lands after the balance rise that preceded it.
    private func reloadHistoryState() {
        let activities = session.recentActivities(limit: Self.recentFetchCount)
        let addedMoney = session.hasEverAddedMoney()

        guard activities != recentActivities
                || addedMoney != hasAddedMoney
        else { return }

        withAnimation(.default) {
            recentActivities = activities
            hasAddedMoney = addedMoney
        }
    }

    /// Pure balance → view-data projection, shared by the synchronous seed and
    /// `refresh()`.
    private static func snapshot(
        session: Session,
        rate: Rate
    ) -> (cards: [TokenCardData], total: ExchangedFiat, appreciation: (amount: FiatAmount, isPositive: Bool)) {
        let all = session.balances(for: rate)
        let visible = Session.walletCardBalances(from: all)

        let cards = TokenCardData.walletCards(for: visible, session: session, rate: rate)

        let total = all.map(\.exchangedFiat).total(rate: rate)

        var net: Decimal = 0
        for balance in all {
            let (value, isPositive) = balance.stored.computeAppreciation(with: rate)
            net += isPositive ? value.nativeAmount.value : -value.nativeAmount.value
        }
        let appreciation = (
            amount: FiatAmount(value: abs(net), currency: rate.currency),
            isPositive: net >= 0
        )

        return (cards, total, appreciation)
    }
}

/// Circular Liquid Glass for the wallet's open-card chrome.
private struct WalletCircleGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .circle)
        } else {
            content.background(.ultraThinMaterial, in: Circle())
        }
    }
}
