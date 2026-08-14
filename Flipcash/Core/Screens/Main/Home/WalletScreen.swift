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

    let session: Session
    let onScanTipCard: () -> Void

    @State private var cards: [TokenCardData] = []
    @State private var total: ExchangedFiat
    @State private var appreciation: (amount: FiatAmount, isPositive: Bool)
    @State private var hasAddedMoney: Bool
    @State private var hasTipped: Bool
    /// The unified recent-activity preview (newest first).
    @State private var recentActivities: [Activity]

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
        }
    }

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

                if !cards.isEmpty {
                    TokenCardStack(
                        items: cards,
                        onCardTap: { router.push(.currencyInfo($0.mint)) }
                    )
                }

                if !recentActivities.isEmpty {
                    recentActivitySection
                }

                // Returning users (already funded) get the tile shortcuts below
                // the activity; new users use the funnel's own steps instead.
                if hasAddedMoney {
                    walletTiles
                        .padding(.top, 24)
                }

                // Bottom inset so the last card clears the floating tab bar.
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
        }
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
        VStack(alignment: .leading, spacing: 0) {
            // The header is the "dive in" affordance — tapping it (or the
            // chevron) opens the full cross-token activity history. The rows
            // themselves are a non-interactive preview.
            Button {
                router.push(.activity)
            } label: {
                HStack(spacing: 6) {
                    Text("Recent")
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 24)
            .padding(.bottom, 4)

            ForEach(recentActivities) { activity in
                WalletActivityRow(activity: activity)
            }
        }
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
