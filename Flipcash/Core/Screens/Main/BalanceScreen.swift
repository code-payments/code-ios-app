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
    
    @Binding var isPresented: Bool
    
    @Environment(RatesController.self) private var ratesController
    @Environment(HistoryController.self) private var historyController
    @Environment(NotificationController.self) private var notificationController


    let session: Session

    @State private var isShowingCurrencySelection: Bool  = false
    @State private var isShowingCurrencyDiscovery: Bool = false
    @State private var dialogItem: DialogItem?
    @State private var selectedActivity: Activity?
    @State private var selectedMint: PublicKey?

    /// Owned, mutable source for the LazyVStack. Reorder animations only fire
    /// when the data source is mutated inside an active animation transaction —
    /// a body-time computed property doesn't satisfy that.
    @State private var sortedBalances: [ExchangedBalance] = []

    /// Synchronizes per-row geometry across reorders so rows slide to their new
    /// positions instead of popping when the sort order shuffles.
    @Namespace private var balanceRowNamespace

    /// USDF is surfaced separately via `reservesBalance`.
    private var currencyBalances: [ExchangedBalance] {
        sortedBalances.filter { $0.stored.mint != .usdf }
    }

    /// `nil` for a zero balance so the reserves row is hidden when there's
    /// nothing to show.
    private var reservesBalance: ExchangedBalance? {
        sortedBalances.first { $0.stored.mint == .usdf && $0.stored.quarks > 0 }
    }

    private var hasBalances: Bool {
        !currencyBalances.isEmpty || reservesBalance != nil
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
    /// avoid re-filtering `currencyBalances` on every body evaluation.
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
    
    init(isPresented: Binding<Bool>, container: Container, sessionContainer: SessionContainer) {
        self._isPresented     = isPresented
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
        NavigationStack {
            Background(color: .backgroundMain) {
                VStack(spacing: 0) {
                    list()
                }
                .sheet(item: $selectedActivity) { activity in
                    PartialSheet(background: .backgroundMain) {
                        TransactionDetailsModal(
                            isPresented: Binding {
                                selectedActivity != nil
                            } set: { _ in
                                selectedActivity = nil
                            },
                            activity: activity
                        ) { metadata in
                            cancelCashLinkAction(activity: activity, metadata: metadata)
                        }
                    }
                }
            }
            .onAppear(perform: onAppear)
            .onChange(of: session.balances, initial: true) { _, _ in refreshSortedBalances() }
            .onChange(of: balanceRate) { _, _ in refreshSortedBalances() }
            .onChange(of: session.pendingCurrencyInfoMint, initial: true) { _, mint in
                guard let mint else { return }
                Analytics.tokenInfoOpened(from: .openedFromDeeplink, mint: mint)
                selectedMint = mint
                session.pendingCurrencyInfoMint = nil
            }
            .navigationTitle("Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedMint) { mint in
                CurrencyInfoScreen(
                    mint: mint,
                    container: container,
                    sessionContainer: sessionContainer
                )
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ToolbarCloseButton(binding: $isPresented)
                }
            }
            .onChange(of: notificationController.pushWillPresent) { _, _ in
                session.updateBalance()
                historyController.sync()
            }
        }
        .dialog(item: $dialogItem)
        .sheet(isPresented: $isShowingCurrencyDiscovery) {
            CurrencyDiscoveryScreen(
                container: container,
                sessionContainer: sessionContainer
            )
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
                isShowingCurrencyDiscovery = true
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 20)
        .containerRelativeFrame(.vertical) { length, _ in length * 0.5 }
    }

    @ViewBuilder private func list() -> some View {
        let appreciation = computeAppreciation(for: currencyBalances)

        // ScrollView ignores the bottom safe area so the section footer pins to
        // the very bottom of the screen — the gradient can then fade out
        // content scrolling under the home-indicator region. The button itself
        // is pushed back into the safe area via `safeAreaInsets.bottom`.
        GeometryReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionFooters]) {
                    Section {
                        VStack {
                            header()
                                .frame(height: 60)

                            ValueAppreciation(amount: appreciation.amount, isPositive: appreciation.isPositive)
                                .padding(.top, 4)
                        }
                        .padding(.vertical, 30)

                        if hasBalances {
                            ForEach(currencyBalances) { balance in
                                CurrencyBalanceRow(exchangedBalance: balance) {
                                    Analytics.tokenInfoOpened(from: .openedFromWallet, mint: balance.stored.mint)
                                    selectedMint = balance.stored.mint
                                }
                                .vSeparator(color: .rowSeparator)
                                .matchedGeometryEffect(id: balance.id, in: balanceRowNamespace)
                            }

                            if let reservesBalance, reservesBalance.exchangedFiat.hasDisplayableValue() {
                                CashReservesRow(
                                    reservesBalance: reservesBalance,
                                    showTopDivider: currencyBalances.isEmpty,
                                    selectedMint: $selectedMint
                                )
                            }
                        } else {
                            emptyState()
                        }
                    } footer: {
                        if hasBalances {
                            Button("Discover Currencies") {
                                isShowingCurrencyDiscovery = true
                            }
                            .buttonStyle(.filled)
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

    @ViewBuilder private func header() -> some View {
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
                CurrencySelectionScreen(
                    isPresented: $isShowingCurrencySelection,
                    kind: .balance,
                    ratesController: ratesController
                )
            }
        }
    }
    
    // MARK: - Action -
        
    private func rowAction(activity: Activity) {
        if let cashLinkMetadata = activity.cancellableCashLinkMetadata {
            cancelCashLinkAction(
                activity: activity,
                metadata: cashLinkMetadata
            )
        }
    }
    
    private func cancelCashLinkAction(activity: Activity, metadata: Activity.CashLinkMetadata) {
        dialogItem = .init(
            style: .destructive,
            title: "Cancel \(activity.exchangedFiat.nativeAmount.formatted()) Transfer?",
            subtitle: "The money will be returned to your wallet.",
            dismissable: true
        ) {
            .destructive("Cancel Transfer") {
                cancelCashLink(metadata: metadata)
            };
            .cancel()
        }
    }
    
    private func cancelCashLink(metadata: Activity.CashLinkMetadata) {
        Task {
            do {
                try await session.cancelCashLink(giftCardVault: metadata.vault)
            } catch {
                ErrorReporting.captureError(error, reason: "Failed to cancel cash link", metadata: [
                    "vault": metadata.vault.base58,
                ])
                dialogItem = .init(
                    style: .destructive,
                    title: "Failed to Cancel Transfer",
                    subtitle: "Something went wrong. Please try again later",
                    dismissable: true
                ) {
                    .okay(kind: .destructive)
                }
            }
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
