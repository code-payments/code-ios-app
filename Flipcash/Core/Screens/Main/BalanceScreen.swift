//
//  BalanceScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-04-23.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct BalanceScreen: View {

    @Environment(AppRouter.self) private var router
    @Environment(RatesController.self) private var ratesController
    @Environment(HistoryController.self) private var historyController
    @Environment(NotificationController.self) private var notificationController


    let session: Session

    /// Owned, mutable source for the LazyVStack. Reorder animations only fire
    /// when the data source is mutated inside an active animation transaction —
    /// a body-time computed property doesn't satisfy that.
    @State private var sortedBalances: [ExchangedBalance] = []

    /// Synchronizes per-row geometry across reorders so rows slide to their new
    /// positions instead of popping when the sort order shuffles.
    @Namespace private var balanceRowNamespace

    private var hasBalances: Bool {
        !sortedBalances.isEmpty
    }

    private var balance: ExchangedFiat {
        sortedBalances.map(\.exchangedFiat).total(rate: balanceRate)
    }

    private let container: Container
    private let sessionContainer: SessionContainer

    private var balanceRate: Rate {
        ratesController.rateForBalanceCurrency()
    }

    /// Takes balances by parameter so callers can pass a cached snapshot and
    /// avoid re-iterating `sortedBalances` on every body evaluation.
    private func computeAppreciation(for balances: [ExchangedBalance]) -> (amount: FiatAmount, isPositive: Bool) {
        var totalAppreciation: Decimal = 0

        for balance in balances {
            let (value, isPositive) = balance.stored.computeAppreciation(with: balanceRate)
            let amount = value.nativeAmount.value
            totalAppreciation += isPositive ? amount : -amount
        }

        let isPositive = totalAppreciation >= 0
        let amount = FiatAmount(value: abs(totalAppreciation), currency: balanceRate.currency)
        return (amount, isPositive)
    }

    // MARK: - Init -

    init(container: Container, sessionContainer: SessionContainer) {
        self.container        = container
        self.sessionContainer = sessionContainer
        self.session          = sessionContainer.session
    }

    // MARK: - Lifecycle -

    private func onAppear() {
        historyController.sync()
    }

    // MARK: - Body -

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router[.balance]) {
            Background(color: .backgroundMain) {
                VStack(spacing: 0) {
                    list()
                }
            }
            .onAppear(perform: onAppear)
            .onChange(of: session.balances, initial: true) { _, _ in refreshSortedBalances() }
            .onChange(of: balanceRate) { _, _ in refreshSortedBalances() }
            .navigationTitle("Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .appRouterDestinations(container: container, sessionContainer: sessionContainer)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton(action: router.dismissSheet)
                }
            }
            .onChange(of: notificationController.pushWillPresent) { _, _ in
                session.updateBalance()
                historyController.sync()
            }
        }
    }

    @ViewBuilder private func emptyState() -> some View {
        VStack(spacing: 10) {
            Text("No Balance Yet")
                .font(.appTextLarge)

            Text("Buy your first currency to get started")
                .font(.appTextMedium)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)

            BubbleButton(text: "Discover Currencies") {
                router.push(.discoverCurrencies)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 20)
        .containerRelativeFrame(.vertical) { length, _ in length * 0.5 }
    }

    @ViewBuilder private func list() -> some View {
        let appreciation = computeAppreciation(for: sortedBalances)

        // ScrollView ignores the bottom safe area so the section footer pins to
        // the very bottom of the screen — the gradient can then fade out
        // content scrolling under the home-indicator region. The button itself
        // is pushed back into the safe area via `safeAreaInsets.bottom`.
        GeometryReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionFooters]) {
                    Section {
                        VStack {
                            BalanceHeaderButton(balance: balance)
                                .frame(height: 60)

                            ValueAppreciation(amount: appreciation.amount, isPositive: appreciation.isPositive)
                                .padding(.top, 4)
                        }
                        .padding(.vertical, 30)

                        if hasBalances {
                            ForEach(sortedBalances) { balance in
                                CurrencyBalanceRow(
                                    exchangedBalance: balance,
                                    accessibilityIdentifier: balance.stored.mint == .usdf ? "currency-row-usdf" : "currency-row"
                                ) {
                                    Analytics.tokenInfoOpened(from: .openedFromWallet, mint: balance.stored.mint)
                                    router.push(.currencyInfo(balance.stored.mint))
                                }
                                .vSeparator(color: .rowSeparator)
                                .matchedGeometryEffect(id: balance.id, in: balanceRowNamespace)
                            }
                        } else {
                            emptyState()
                        }
                    } footer: {
                        if hasBalances {
                            CodeButton(style: .filledSecondary, title: "Discover Currencies") {
                                router.push(.discoverCurrencies)
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .padding(.bottom, 20 + proxy.safeAreaInsets.bottom)
                            .frame(maxWidth: .infinity)
                            .background {
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.backgroundMain, Color.backgroundMain, .clear]),
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            }
                        }
                    }
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
    }

    /// Wrapped in `withAnimation` so the LazyVStack diff joins an animation
    /// transaction — `matchedGeometryEffect` then interpolates each row to its
    /// new slot when the sort order shuffles.
    private func refreshSortedBalances() {
        let next = session.balances(for: balanceRate)
        guard next != sortedBalances else { return }
        withAnimation(.smooth) {
            sortedBalances = next
        }
    }

}

struct ExchangedBalance: Identifiable, Hashable {
    let stored: StoredBalance
    let exchangedFiat: ExchangedFiat

    var id: PublicKey {
        stored.id
    }
}

extension StoredBalance {
    func exchanged(with rate: Rate) -> ExchangedBalance {
        ExchangedBalance(stored: self, exchangedFiat: computeExchangedValue(with: rate))
    }
}

private struct BalanceHeaderButton: View {
    let balance: ExchangedFiat

    @Environment(RatesController.self) private var ratesController
    @State private var isShowingCurrencySelection = false

    var body: some View {
        VStack(spacing: 10) {
            Button {
                isShowingCurrencySelection.toggle()
            } label: {
                AmountText(
                    flagStyle: balance.nativeAmount.currency.flagStyle,
                    content: balance.nativeAmount.formatted(),
                    showChevron: true
                )
                .font(.appDisplayLarge)
                .foregroundStyle(Color.textMain)
                .contentTransition(.numericText())
            }
            .accessibilityIdentifier("balance-header")
            .frame(maxWidth: .infinity)
            .animation(.default, value: balance)
            .sheet(isPresented: $isShowingCurrencySelection) {
                CurrencySelectionScreen(ratesController: ratesController)
            }
        }
    }
}
