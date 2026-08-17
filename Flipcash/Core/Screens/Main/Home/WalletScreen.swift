//
//  WalletScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// The v2 Wallet tab: the big balance header, per-token bill cards in a
/// collapsing ``TokenCardStack``, and an add-money affordance. Replaces the v1
/// ``BalanceScreen`` list in the tab-bar UI. Owns its own `NavigationStack` bound
/// to `router[.balance]`, so the existing push destinations (currency info,
/// transaction history) work unchanged.
struct WalletScreen: View {

    @Environment(SessionContainer.self) private var sessionContainer

    /// Invoked by the funnel's "Scan a Tip Card" step to switch to the Scan tab.
    let onScanTipCard: () -> Void

    var body: some View {
        WalletScreenContent(sessionContainer: sessionContainer, onScanTipCard: onScanTipCard)
    }
}

private struct WalletScreenContent: View {

    @Environment(AppRouter.self) private var router
    @Environment(RatesController.self) private var ratesController
    @Environment(HistoryController.self) private var historyController
    /// Reported so the tab bar hides while a card is open — the expansion is an
    /// overlay, so the usual push-based rule does not see it.
    @Environment(WalletCardExpansion.self) private var cardExpansion

    let session: Session
    let onScanTipCard: () -> Void

    @State private var cards: [TokenCardData] = []
    @State private var total: ExchangedFiat
    @State private var appreciation: (amount: FiatAmount, isPositive: Bool)
    @State private var hasAddedMoney: Bool
    @State private var hasTipped: Bool
    /// The unified recent-activity preview (newest first).
    @State private var recentActivities: [Activity]

    /// The card being opened. The deck reorganises around it and the detail
    /// panel rises beneath it.
    @State private var expandingMint: PublicKey?
    /// How far the page's hero card is displaced from its resting slot. Seeded
    /// with the tapped card's position in the deck and animated to zero, so the
    /// card the page shows *is* the card that travels — there is no copy laid
    /// over the top, and it belongs to the page's scroll view the whole time.
    @State private var heroOffset: CGFloat = 0
    /// The slot the deck leaves empty while that card is drawn elsewhere.
    @State private var hiddenMint: PublicKey?
    /// Released once the transition has settled, letting the page build its
    /// chart and read its activity without stuttering the animation.
    @State private var heavyContentReady = false
    /// Brings the page in behind the travelling card: everything except the
    /// card itself, which is continuous.
    @State private var pageContentOpacity: Double = 0
    /// Whether the page exists yet. Split from its fade so the cost of
    /// building it is paid on its own runloop turn, while the card is already
    /// in flight, rather than on the frame it becomes visible.
    @State private var pageIsBuilt = false
    /// Fades the wallet — balance header included — out behind the opening card.
    @State private var deckOpacity: Double = 1
    /// Where a pull-to-close let go of the card, so the deck picks it up there
    /// rather than snapping it back to its open slot first. Animated to zero as
    /// the close carries it home.
    @State private var releasedPullOffset: CGFloat = 0
    /// Drives the deck's reorganisation, 0 (resting) to 1 (cleared), animated in
    /// lockstep with the card's flight so the two read as one gesture.
    @State private var expansionProgress: CGFloat = 0
    /// Identifies the transition currently in flight. Opening and closing both
    /// finish their work in callbacks — an animation completion, and a delayed
    /// page fade — which keep running even once the transition that scheduled
    /// them has been replaced. Each captures the token it started with and does
    /// nothing if it no longer matches, so a close settling in the background
    /// cannot tear down the open that interrupted it.
    @State private var transitionToken = 0
    /// Size of the wallet's container, used to push the lower cards off-screen
    /// and to size the detail panel below the open card.
    @State private var containerSize: CGSize = .zero

    /// Safe-area insets: the wallet's container excludes them, so they are added
    /// back when sizing the panel against the full screen.
    @State private var safeArea: EdgeInsets = .init()

    private var safeAreaTop: CGFloat { safeArea.top }

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

    /// Rows of recent activity previewed on the wallet (the rest lives on the
    /// per-token transaction history).
    private static let recentPreviewCount = 3

    init(sessionContainer: SessionContainer, onScanTipCard: @escaping () -> Void) {
        self.session = sessionContainer.session
        self.onScanTipCard = onScanTipCard
        let rate = sessionContainer.ratesController.rateForBalanceCurrency()
        // Seed synchronously so the first render shows real balances, not an
        // empty-state flash (mirrors BalanceScreen).
        let seed = Self.snapshot(session: sessionContainer.session, rate: rate)
        _cards = State(initialValue: seed.cards)
        _total = State(initialValue: seed.total)
        _appreciation = State(initialValue: seed.appreciation)
        _hasAddedMoney = State(initialValue: seed.hasAddedMoney)
        _hasTipped = State(initialValue: seed.hasTipped)
        _recentActivities = State(initialValue: sessionContainer.session.recentActivities(limit: Self.recentPreviewCount))
    }

    private var rate: Rate { ratesController.rateForBalanceCurrency() }

    private var isOnboardingComplete: Bool { hasAddedMoney && hasTipped }

    private var onboardingItems: [OnboardingItem] {
        [.addMoney(isCompleted: hasAddedMoney), .scanTipCard(isCompleted: hasTipped)]
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router[.balance]) {
            Background(color: .backgroundMain) {
                walletContent
            }
            // Once the deck has finished reorganising, the currency info screen
            // takes over the whole screen with its hero card on the same spot the
            // wallet parked the opened card — so the swap is invisible and the
            // page scrolls as one, card included.
            .overlay {
                // Built once the card is already in flight, but held invisible
                // until it is most of the way there.
                if pageIsBuilt, let expandingMint {
                    CurrencyInfoScreen(
                        mint: expandingMint,
                        presentation: .overlay(
                            onClose: { closeCard() },
                            heroOffset: heroOffset,
                            contentOpacity: pageContentOpacity,
                            onPull: scrubDismiss,
                            onPullEnded: endDismiss
                        ),
                        defersHeavyContent: !heavyContentReady
                    )
                    .id(expandingMint)
                    // Fades in behind the card rather than sliding, which would
                    // drag the chrome and tiles in from the bottom. The deck is
                    // clearing underneath, so nothing shows through.
                    .background(Color.backgroundMain.opacity(pageContentOpacity))
                    // Deliberately no edge-swipe back. The screen is lifted over
                    // the wallet rather than pushed onto it, and its chrome says
                    // so with a close box instead of a back chevron.
                }
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { containerSize = $0 }
            .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { safeArea = $0 }
            // No top bar on the wallet root (per Figma) — the balance header
            // sits directly under the status bar. Pushed destinations restore
            // their own nav bar.
            .toolbar(.hidden, for: .navigationBar)
            .appRouterDestinations()
            .onAppear { historyController.sync() }
            .onChange(of: session.balances) { _, _ in refresh() }
            .onChange(of: rate) { _, _ in refresh() }
            // Activities land in the DB independently of a balance change (e.g.
            // a synced history page), so reload the preview on any DB change.
            .onReceive(NotificationCenter.default.publisher(for: .databaseDidChange)) { _ in
                recentActivities = session.recentActivities(limit: Self.recentPreviewCount)
            }
            // Popping back to the wallet restores the deck.
            // Deliberately not watching the stack depth to decide whether the
            // card is still open. The opened card is an overlay, not a stack
            // entry, so an empty stack is its *normal* state — pushing the full
            // transaction history and popping back returns the depth to zero,
            // which a depth watcher reads as "back at the wallet" and closes the
            // card out from under the screen the user was returning to.
        }
        .environment(\.walletCardNamespace, cardNamespace)
    }

    /// Opens a token: the deck reorganises around the tapped card, which stays
    /// on screen while the detail panel rises beneath it.
    private func openCard(_ item: TokenCardData, currentTop: CGFloat) {
        transitionToken &+= 1
        let token = transitionToken

        // Everything that costs a frame happens in this one un-animated step, so
        // the animation that follows is pure interpolation.
        var seed = Transaction()
        seed.disablesAnimations = true
        withTransaction(seed) {
            // The page's own hero card starts over the deck slot the tapped
            // card occupies, so the two coincide exactly on the first frame.
            heroOffset = (currentTop - safeArea.top) - WalletCardGeometry.openCardTopInset
            pageContentOpacity = 0
            pageIsBuilt = false
            expansionProgress = 0
            expandingMint = item.mint
            hiddenMint = item.mint
            // Both of these block the main thread for a few frames — hiding the
            // tab bar relayouts the whole `TabView`, and building the page runs
            // its view model's synchronous metadata read and decode. They are
            // done here, before the animation below is committed, so the cost
            // lands as a short pause on the tap rather than as a stall part-way
            // through the flight. SwiftUI's spring animations are driven on the
            // main thread, so work deferred until *after* the commit does not
            // run alongside the motion — it interrupts it.
            cardExpansion.isExpanded = true
            pageIsBuilt = true
        }

        // The card's flight and the deck's reorganisation are one animation: the
        // cards above collapse into the opened card's slot and the ones below run
        // off the bottom exactly as it lifts away.
        //
        // The hand-off is driven by the animation finishing rather than by a
        // matching sleep: a spring is still settling when its nominal duration
        // is up, so on a timer the flying card is still short of its mark when
        // the page's hero card appears at the final position. The two are then
        // drawn a few points apart, which reads as the card juddering into
        // place. `.removed` fires once it has actually stopped.
        withAnimation(.smooth(duration: Self.liftDuration), completionCriteria: .removed) {
            heroOffset = 0
            expansionProgress = 1
            deckOpacity = 0
        } completion: {
            guard token == transitionToken else { return }
            // Everything has come to rest, so the chart can fetch its points and
            // draw for real inside the space it has been holding all along.
            heavyContentReady = true
        }

        Task {
            // The card leads; the page follows it in, so the motion reads as one
            // gesture instead of the content arriving on its own. Sized to finish
            // just before the card lands, so the hero card it hands over to is
            // fully opaque by then.
            try? await Task.sleep(for: .seconds(Self.pageFollowDelay))
            guard token == transitionToken else { return }
            withAnimation(.smooth(duration: Self.liftDuration - Self.pageFollowDelay)) {
                pageContentOpacity = 1
            }
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

    /// Runs the opening backwards under a pull-to-close, so the screen recedes
    /// Recedes the screen under a pull-to-close: the info content and chrome
    /// fade out. The deck is deliberately left as it
    /// is — reassembling it under the finger leaves the card nothing to hand
    /// over to when the drag ends, and the stack reading through a half-faded
    /// page is not what the gesture should look like anyway. It comes back on
    /// release, carrying the card home with it.
    ///
    /// The card's *position* is left alone too: the scroll view's overscroll
    /// already carries it down a point per point, and driving its journey back
    /// to the deck on top of that sends it several times faster than the drag.
    ///
    /// Un-animated on purpose. This tracks a finger, so each update is the
    /// current position rather than something to interpolate towards.
    private func scrubDismiss(_ progress: CGFloat) {
        guard expandingMint != nil else { return }
        var tracking = Transaction()
        tracking.disablesAnimations = true
        withTransaction(tracking) { pageContentOpacity = 1 - progress }
    }

    /// The finger lifted: either carry the dismissal through, or put everything
    /// back where it was.
    private func endDismiss(_ passedThreshold: Bool, _ releasedAt: CGFloat) {
        guard expandingMint != nil else { return }
        if passedThreshold {
            closeCard(resumingFrom: releasedAt)
        } else {
            withAnimation(.smooth(duration: 0.25)) { pageContentOpacity = 1 }
        }
    }

    /// Closes a token: the reverse of opening. The page drops away and the deck
    /// takes its card back, sliding it down into its own slot and under the
    /// cards stacked on top of it — put back, rather than simply vanishing.
    private func closeCard(resumingFrom pullOffset: CGFloat = 0) {
        guard expandingMint != nil else { return }
        transitionToken &+= 1
        let token = transitionToken

        // Hand the card to the deck before anything moves. It is already sitting
        // at the open position (the stack holds it there while `progress` is 1),
        // so this swap is invisible — and from here the deck owns the return,
        // which is what lets the card go *under* its neighbours on the way home.
        var handback = Transaction()
        handback.disablesAnimations = true
        withTransaction(handback) {
            hiddenMint = nil
            // Hand the card over at the height the finger left it at, so the
            // close picks up from there instead of jumping back to the open slot
            // and replaying from the top.
            releasedPullOffset = pullOffset
            pageContentOpacity = 0
            pageIsBuilt = false
            heavyContentReady = false
            // Brought back here, before the motion, for the same reason it is
            // hidden before the opening one: restoring it relayouts the whole
            // `TabView`. Left until the animation finishes, that cost lands
            // *after* the deck has settled and the bar visibly arrives late.
            cardExpansion.isExpanded = false
        }

        // `expandingMint` has to stay put for the duration: it is the anchor the
        // reorganisation is measured against, and clearing it here would swap the
        // deck back to its resting formula in one frame instead of unwinding it.
        withAnimation(.smooth(duration: Self.liftDuration), completionCriteria: .removed) {
            expansionProgress = 0
            deckOpacity = 1
            releasedPullOffset = 0
        } completion: {
            // Only if this close is still the current transition: tapping a card
            // again while it settles starts an open, and clearing the anchor then
            // would strand the wallet with its header faded out and no page.
            guard token == transitionToken else { return }
            // The deck is back in its resting fan, so the anchor can go. Waiting
            // for the animation rather than a matching sleep matters here too:
            // clearing it while the spring is still settling drops the cards the
            // last few points in one frame.
            withTransaction(handback) {
                expandingMint = nil
            }
        }
    }

    private static let liftDuration: TimeInterval = 0.32
    /// How far behind the card the page follows.
    private static let pageFollowDelay: TimeInterval = 0.20

    // MARK: - Content

    private var walletContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                // Header + funnel scroll off first; the card stack then reaches the
                // top and collapses into its back card. The stack measures the
                // scroll itself (via `.visualEffect`), so no height plumbing here.
                VStack(spacing: 0) {
                    header
                        // Figma (8966:1578) drops the balance well down the screen —
                        // most of the extra space sits above it, less below.
                        .padding(.top, 96)
                        .padding(.bottom, 44)

                    if !isOnboardingComplete {
                        OnboardingFunnelView(
                            title: "Send Your First Tip",
                            items: onboardingItems,
                            onTap: handleOnboardingTap
                        )
                        .padding(.bottom, 20)
                    }
                }
                // The stack is deliberately outside the fade: its cards carry
                // their own, driven by the same progress, so the opened one can
                // stay solid while the rest of the deck goes.
                .opacity(deckOpacity)

                if !cards.isEmpty {
                    TokenCardStack(
                        items: cards,
                        namespace: cardNamespace,
                        expandingMint: expandingMint,
                        expansionProgress: expansionProgress,
                        containerHeight: containerSize.height,
                        hiddenMint: hiddenMint,
                        openTopInset: WalletCardGeometry.openCardTopInset,
                        openExtraOffset: releasedPullOffset,
                        onCardTap: openCard
                    )
                }

                Group {
                    if !recentActivities.isEmpty {
                        recentActivitySection
                    }

                    // Returning users (already funded) get the tile shortcuts
                    // below the activity; new users use the funnel's own steps
                    // instead.
                    if hasAddedMoney {
                        walletTiles
                            .padding(.top, 24)
                    }
                }
                .opacity(deckOpacity)

                // Bottom inset so the last card clears the floating tab bar.
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
        }
        // Gated on the page being up rather than on `expandingMint`, which is
        // held until the closing spring is fully removed — a good deal later
        // than it looks finished. Tying the lock to it left the wallet inert for
        // that tail: a swipe found a disabled scroll view and fell through to
        // the card underneath as a tap.
        .scrollDisabled(pageIsBuilt)
    }

    private var header: some View {
        VStack(spacing: 4) {
            BalanceHeaderButton(balance: total)
                .frame(height: 60)
            ValueAppreciation(amount: appreciation.amount, isPositive: appreciation.isPositive, style: .pill)
        }
    }

    private var walletTiles: some View {
        HStack(spacing: 12) {
            walletTile(icon: "plus.circle", title: "Add Money") {
                router.presentAddMoney(.general, source: .balance)
            }
            walletTile(icon: "globe", title: "Discover Currencies") {
                router.push(.discoverCurrencies)
            }
        }
    }

    /// A tile-style entry point: icon top-leading, label pinned bottom-leading,
    /// inside a translucent rounded card. Two pair side by side in a row.
    private func walletTile(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .regular))
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
            .clipShape(RoundedRectangle(cornerRadius: Metrics.boxRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var recentActivitySection: some View {
        // The header opens the full cross-token history here; currency info
        // passes its own per-token destination.
        RecentActivitySection(activities: recentActivities) {
            router.push(.activity)
        }
        .padding(.top, 24)
    }

    private func handleOnboardingTap(_ item: OnboardingItem) {
        switch item {
        case .addMoney:
            router.presentAddMoney(.general, source: .balance)
        case .scanTipCard:
            onScanTipCard()
        }
    }

    // MARK: - Data

    private func refresh() {
        let snapshot = Self.snapshot(session: session, rate: rate)
        withAnimation(.default) {
            cards = snapshot.cards
            total = snapshot.total
            appreciation = snapshot.appreciation
            hasAddedMoney = snapshot.hasAddedMoney
            hasTipped = snapshot.hasTipped
        }
    }

    /// Pure balance → view-data projection, shared by the synchronous seed and
    /// `refresh()`. Resolves each token's bill colors once (a DB read per token)
    /// rather than per body evaluation.
    private static func snapshot(
        session: Session,
        rate: Rate
    ) -> (cards: [TokenCardData], total: ExchangedFiat, appreciation: (amount: FiatAmount, isPositive: Bool), hasAddedMoney: Bool, hasTipped: Bool) {
        let all = session.balances(for: rate)
        let visible = all.filter { $0.stored.mint != .usdf || $0.exchangedFiat.hasDisplayableValue() }

        let cards = visible.map { balance -> TokenCardData in
            let (value, isPositive) = balance.stored.computeAppreciation(with: rate)
            // The pill always shows (per Figma). A sub-cent value rounds to
            // "$0.00" and reads as positive, so a tiny negative never renders "-$0.00".
            let roundsToZero = value.nativeAmount.value < 0.005
            let appreciationText = (isPositive || roundsToZero ? "+" : "-") + value.nativeAmount.formatted()
            return TokenCardData(
                mint: balance.stored.mint,
                name: balance.stored.name,
                imageURL: balance.stored.imageURL,
                balanceText: balance.exchangedFiat.nativeAmount.formatted(),
                appreciationText: appreciationText,
                colors: session.billColors(for: balance.stored.mint),
                isUSDF: balance.stored.mint == .usdf
            )
        }

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

        return (cards, total, appreciation, session.hasEverAddedMoney(), session.hasEverTipped())
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
