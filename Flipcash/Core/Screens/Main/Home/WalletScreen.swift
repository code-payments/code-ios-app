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

    var body: some View {
        WalletScreenContent(sessionContainer: sessionContainer)
    }
}

/// Bubbles the token stack's top offset (px scrolled above the viewport top) up
/// to the scroll view so the stack can collapse as it scrolls.
private struct StackScrollKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct WalletScreenContent: View {

    @Environment(AppRouter.self) private var router
    @Environment(RatesController.self) private var ratesController
    @Environment(HistoryController.self) private var historyController

    let session: Session

    @State private var cards: [TokenCardData] = []
    @State private var total: ExchangedFiat
    @State private var appreciation: (amount: FiatAmount, isPositive: Bool)
    @State private var scrolledPast: CGFloat = 0

    private static let scrollSpace = "walletScroll"

    init(sessionContainer: SessionContainer) {
        self.session = sessionContainer.session
        let rate = sessionContainer.ratesController.rateForBalanceCurrency()
        // Seed synchronously so the first render shows real balances, not an
        // empty-state flash (mirrors BalanceScreen).
        let seed = Self.snapshot(session: sessionContainer.session, rate: rate)
        _cards = State(initialValue: seed.cards)
        _total = State(initialValue: seed.total)
        _appreciation = State(initialValue: seed.appreciation)
    }

    private var rate: Rate { ratesController.rateForBalanceCurrency() }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router[.balance]) {
            Background(color: .backgroundMain) {
                Group {
                    if cards.isEmpty {
                        emptyState
                    } else {
                        walletContent
                    }
                }
            }
            .navigationTitle("Wallet")
            .toolbarTitleDisplayMode(.inline)
            .appRouterDestinations()
            .onAppear { historyController.sync() }
            .onChange(of: session.balances) { _, _ in refresh() }
            .onChange(of: rate) { _, _ in refresh() }
        }
    }

    // MARK: - Content

    private var walletContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                    .padding(.vertical, 30)

                TokenCardStack(
                    items: cards,
                    scrolledPast: scrolledPast,
                    onCardTap: { router.push(.currencyInfo($0.mint)) }
                )
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: StackScrollKey.self,
                            value: -proxy.frame(in: .named(Self.scrollSpace)).minY
                        )
                    }
                )

                addMoneyButton
                    .padding(.top, 24)

                // Bottom inset so the last card clears the floating tab bar.
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
        }
        .coordinateSpace(name: Self.scrollSpace)
        .onPreferenceChange(StackScrollKey.self) { scrolledPast = max(0, $0) }
    }

    private var header: some View {
        VStack(spacing: 4) {
            BalanceHeaderButton(balance: total)
                .frame(height: 60)
            ValueAppreciation(amount: appreciation.amount, isPositive: appreciation.isPositive)
        }
    }

    private var addMoneyButton: some View {
        Button {
            router.presentAddMoney(.general, source: .balance)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                Text("Add Money")
            }
            .font(.appTextMedium)
            .foregroundStyle(Color.textSecondary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("No Balance Yet")
                .font(.appTextLarge)
            Text("Add money to get started")
                .font(.appTextMedium)
                .foregroundStyle(Color.textSecondary)
            BubbleButton(text: "Add Money") {
                router.presentAddMoney(.general, source: .balance)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Data

    private func refresh() {
        let snapshot = Self.snapshot(session: session, rate: rate)
        withAnimation(.default) {
            cards = snapshot.cards
            total = snapshot.total
            appreciation = snapshot.appreciation
        }
    }

    /// Pure balance → view-data projection, shared by the synchronous seed and
    /// `refresh()`. Resolves each token's bill colors once (a DB read per token)
    /// rather than per body evaluation.
    private static func snapshot(
        session: Session,
        rate: Rate
    ) -> (cards: [TokenCardData], total: ExchangedFiat, appreciation: (amount: FiatAmount, isPositive: Bool)) {
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

        return (cards, total, appreciation)
    }
}
