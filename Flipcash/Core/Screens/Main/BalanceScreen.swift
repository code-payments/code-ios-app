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
    
    @EnvironmentObject private var ratesController: RatesController
    @EnvironmentObject private var historyController: HistoryController
    @EnvironmentObject private var notificationController: NotificationController
    
    @ObservedObject private var session: Session
    
    @State private var isShowingCurrencySelection: Bool  = false
    @State private var dialogItem: DialogItem?
    @State private var selectedActivity: Activity?
    @State private var selectedBalance: ExchangedBalance?
    
    private var balance: ExchangedFiat {
        session.totalBalance
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
            .navigationTitle("Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedBalance) { balance in
                CurrencyInfoScreen(
                    mint: balance.stored.mint,
                    container: container,
                    sessionContainer: sessionContainer
                )
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarCloseButton(binding: $isPresented)
                }
            }
            .onChange(of: notificationController.pushWillPresent) { _, _ in
                session.updateBalance()
                historyController.sync()
            }
        }
        .dialog(item: $dialogItem)
    }
    
    @ViewBuilder private func emptyState(geometry: GeometryProxy) -> some View {
        VStack(spacing: 10) {
            Text("No Balance Yet")
                .font(.appTextLarge)
            Text("Get another Flipcash user to give you some cash to get a balance")
                .font(.appTextMedium)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
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
                                selectedBalance = balance
                            }
                        }
                    } else {
                        emptyState(geometry: g)
                    }

                } header: {
                    header()
                        .frame(height: 80)
                        .padding(.vertical, 50)
                } footer: {
                    if let reservesBalance {
                        cashReservesFooter(reservesBalance: reservesBalance)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparatorTint(hasBalances ? .rowSeparator : .clear)
            }
            .listStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder private func cashReservesFooter(reservesBalance: ExchangedBalance) -> some View {
        VStack {
            Divider()
            
            Button {
                selectedBalance = reservesBalance
            } label: {
                HStack(spacing: 8) {
                    Text("Cash Reserves")
                        .font(.appBarButton)
                        .foregroundStyle(Color.textSecondary)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                        .padding(.top, 3)

                    Spacer()

                    Text(reservesBalance.exchangedFiat.converted.formatted())
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                }
            }
                .listRowBackground(Color.clear)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .textCase(.none)
            
            Divider()
        }
        
    }
    
    @ViewBuilder private func header() -> some View {
        VStack(spacing: 10) {
            Button {
                isShowingCurrencySelection.toggle()
            } label: {
                VStack {
                    GeometryReader { g in
                        VStack {
                            AmountText(
                                flagStyle: balance.converted.currencyCode.flagStyle,
                                content: balance.converted.formatted(),
                                showChevron: true
                            )
                            .font(.appDisplayMedium)
                            .foregroundStyle(Color.textMain)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
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
            title: "Cancel \(activity.exchangedFiat.converted.formatted()) Transfer?",
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
