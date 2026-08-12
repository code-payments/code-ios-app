//
//  WalletScreen.swift
//  Flipcash
//

import SwiftUI
import UIKit
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

/// The header block's height — the scroll distance at which the stack reaches
/// the top and the collapse begins. Measured once at layout (scroll-independent).
private struct HeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 150
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
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
    @State private var scrolledPast: CGFloat = 0

    /// Rows of recent activity previewed on the wallet (the rest lives on the
    /// per-token transaction history).
    private static let recentPreviewCount = 3
    /// The height of everything above the card stack (header + funnel) — the
    /// scroll distance before the stack reaches the top. Collapse starts past it.
    @State private var headerHeight: CGFloat = 150
    /// The scroll view's content offset at rest, captured on the first KVO tick.
    @State private var restOffset: CGFloat?

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
                // Header + funnel scroll off before the stack collapses, so their
                // combined height (scroll-independent, measured once at layout) is
                // the collapse threshold.
                VStack(spacing: 0) {
                    header
                        .padding(.vertical, 30)

                    if !isOnboardingComplete {
                        OnboardingFunnelView(
                            title: "Send Your First Tip",
                            items: onboardingItems,
                            onTap: handleOnboardingTap
                        )
                        .padding(.bottom, 20)
                    }
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: HeaderHeightKey.self, value: proxy.size.height)
                    }
                )

                if !cards.isEmpty {
                    TokenCardStack(
                        items: cards,
                        scrolledPast: scrolledPast,
                        onCardTap: { router.push(.currencyInfo($0.mint)) }
                    )
                }

                // Returning users (already funded) get a plain add-money row; new
                // users use the funnel's own "Add Money" step instead.
                if hasAddedMoney {
                    addMoneyButton
                        .padding(.top, 24)
                }

                if !recentActivities.isEmpty {
                    recentActivitySection
                }

                // Bottom inset so the last card clears the floating tab bar.
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            // The underlying UIScrollView's contentOffset updates on every scroll
            // frame — SwiftUI preferences in scroll content only fire at layout —
            // so it, not a GeometryReader, is what drives the collapse. Once the
            // scroll passes the header (the stack reaches the top), the excess is
            // how far the stack has scrolled past the top.
            .background(ScrollOffsetReader { offsetY in
                if restOffset == nil { restOffset = offsetY }
                scrolledPast = max(0, (offsetY - (restOffset ?? 0)) - headerHeight)
            })
        }
        .onPreferenceChange(HeaderHeightKey.self) { headerHeight = $0 }
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

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent")
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 24)
                .padding(.bottom, 4)

            ForEach(recentActivities) { activity in
                WalletActivityRow(activity: activity) {
                    router.push(.transactionHistory(activity.exchangedFiat.mint))
                }
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

/// Reports the enclosing `UIScrollView`'s vertical content offset on every scroll
/// frame. SwiftUI preferences on scroll content only fire at layout time (not
/// during scroll), so this KVO bridge is what makes the card stack collapse.
private struct ScrollOffsetReader: UIViewRepresentable {

    let onChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        // The scroll view isn't in the hierarchy yet during makeUIView; defer.
        DispatchQueue.main.async { context.coordinator.attach(from: view) }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    // KVO on `contentOffset` fires on the main thread for a UIScrollView; the
    // unchecked conformance documents that the stored closure is only ever
    // touched there.
    final class Coordinator: @unchecked Sendable {
        private let onChange: (CGFloat) -> Void
        private var observation: NSKeyValueObservation?

        init(onChange: @escaping (CGFloat) -> Void) { self.onChange = onChange }

        func attach(from view: UIView) {
            var current: UIView? = view.superview
            while let candidate = current {
                if let scrollView = candidate as? UIScrollView {
                    observation = scrollView.observe(\.contentOffset, options: [.initial, .new]) { [weak self] _, change in
                        guard let self, let y = change.newValue?.y else { return }
                        MainActor.assumeIsolated { self.onChange(y) }
                    }
                    return
                }
                current = candidate.superview
            }
        }

        deinit { observation?.invalidate() }
    }
}
