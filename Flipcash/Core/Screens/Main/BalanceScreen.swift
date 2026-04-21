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
    
    private var balance: ExchangedFiat {
        balances.map(\.exchangedFiat).total(rate: balanceRate)
    }
    
    private let proportion: CGFloat = 0.4
    
    private let container: Container
    private let sessionContainer: SessionContainer
    
    private var balanceRate: Rate {
        ratesController.rateForBalanceCurrency()
    }
    
    private var balances: [ExchangedBalance] {
        session.balances(for: balanceRate)
    }

    private var currencyBalances: [ExchangedBalance] {
        balances.filter { $0.stored.mint != .usdf }
    }

    private var reservesBalance: ExchangedBalance? {
        balances.first { $0.stored.mint == .usdf && $0.stored.quarks > 0 }
    }
    
    private var appreciation: (amount: Quarks, isPositive: Bool) {
        var totalAppreciation: Decimal = 0

        for balance in currencyBalances {
            let (value, isPositive) = balance.stored.computeAppreciation(with: balanceRate)
            let amount = value.nativeAmount.value
            totalAppreciation += isPositive ? amount : -amount
        }

        let isPositive = totalAppreciation >= 0
        let quarks = try! Quarks(
            fiatDecimal: abs(totalAppreciation),
            currencyCode: balanceRate.currency,
            decimals: PublicKey.usdf.mintDecimals
        )

        return (quarks, isPositive)
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
    
    @ViewBuilder private func emptyState(geometry: GeometryProxy) -> some View {
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
        .listRowBackground(Color.clear)
        .frame(height: geometry.size.height * (1 - proportion - 0.1))
        .padding(.horizontal, 20)
    }
    
    @ViewBuilder private func list() -> some View {
        let hasBalances = !currencyBalances.isEmpty || reservesBalance != nil
        GeometryReader { g in
            List {
                Section {
                    if hasBalances {
                        ForEach(currencyBalances) { balance in
                            CurrencyBalanceRow(exchangedBalance: balance) {
                                Analytics.tokenInfoOpened(from: .openedFromWallet, mint: balance.stored.mint)
                                selectedMint = balance.stored.mint
                            }
                        }
                    } else {
                        emptyState(geometry: g)
                    }

                } header: {
                    VStack {
                        header()
                            .frame(height: 60)

                        ValueAppreciation(amount: appreciation.amount, isPositive: appreciation.isPositive)
                            .padding(.top, 4)
                    }
                    // iOS 18.6 and earlier: List section headers default to .textCase(.uppercase),
                    // which propagates into child views and sheets presented from within the header.
                    .textCase(.none)
                    .padding(.vertical, 30)
                } footer: {
                    BalanceFooter(
                        reservesBalance: reservesBalance,
                        showDiscoverCurrencies: hasBalances,
                        isOnlyRow: currencyBalances.isEmpty,
                        selectedMint: $selectedMint,
                        isShowingCurrencyDiscovery: $isShowingCurrencyDiscovery
                    )
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(hasBalances ? .automatic : .hidden)
                .listRowSeparatorTint(.rowSeparator)
            }
            .listStyle(.grouped)
            .scrollContentBackground(.hidden)
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
