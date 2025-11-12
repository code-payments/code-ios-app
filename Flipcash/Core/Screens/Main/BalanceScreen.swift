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
    @ObservedObject private var onrampViewModel: OnrampViewModel
    
    @State private var isShowingCurrencySelection: Bool  = false
    @State private var isShowingDepositScreen: Bool      = false
    @State private var isShowingWithdrawFlow: Bool       = false
    
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
    
    // MARK: - Init -
    
    init(isPresented: Binding<Bool>, container: Container, sessionContainer: SessionContainer) {
        self._isPresented     = isPresented
        self.container        = container
        self.sessionContainer = sessionContainer
        self.session          = sessionContainer.session
        self.onrampViewModel  = sessionContainer.onrampViewModel
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
                .sheet(isPresented: $onrampViewModel.isMethodSelectionPresented) {
                    AddCashScreen(
                        isPresented: $onrampViewModel.isMethodSelectionPresented,
                        container: container,
                        sessionContainer: sessionContainer
                    )
                }
                .sheet(isPresented: $onrampViewModel.isOnrampPresented) {
                    PartialSheet(background: .backgroundMain) {
                        PresetAddCashScreen(
                            isPresented: $onrampViewModel.isOnrampPresented,
                            container: container,
                            sessionContainer: sessionContainer
                        )
                    }
                }
            }
            .onAppear(perform: onAppear)
            .navigationTitle("Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $isShowingDepositScreen) {
                DepositDescriptionScreen(
                    container: container,
                    sessionContainer: sessionContainer
                )
            }
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
        .dialog(item: $onrampViewModel.purchaseSuccess)
    }
    
    @ViewBuilder private func emptyState(geometry: GeometryProxy) -> some View {
        VStack {
            Text("Tap above to Add Cash to your wallet")
                .font(.appTextMedium)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
            
//            CodeButton(style: .filled, title: "Deposit Funds") {
//                isShowingDepositScreen.toggle()
//            }
        }
//        .frame(height: geometry.globalHeight * (1 - proportion - 0.1))
        .listRowBackground(Color.clear)
        .padding(.horizontal, 20)
    }
    
    @ViewBuilder private func list() -> some View {
        let hasBalances = !balances.isEmpty
        GeometryReader { g in
            List {
                Section {
                    if hasBalances {
                        ForEach(balances) { balance in
                            CurrencyBalanceRow(exchangedBalance: balance) {
                                selectedBalance = balance
                            }
                        }
                    } else {
                        emptyState(geometry: g)
                    }
                    
                } header: {
                    header()
                        .textCase(.none)
                        .frame(height: g.size.height * proportion)
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparatorTint(hasBalances ? .rowSeparator : .clear)
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
                VStack {
                    GeometryReader { g in
                        VStack {
                            Spacer()
                            
                            AmountText(
                                flagStyle: balance.converted.currencyCode.flagStyle,
                                content: balance.converted.formatted(),
                                showChevron: true
                            )
                            .font(.appDisplayMedium)
                            .foregroundStyle(Color.textMain)
                            .frame(maxWidth: .infinity)
                            
                            Text("Your balance is held in US dollar stablecoins")
                                .font(.appTextSmall)
                                .foregroundStyle(Color.textSecondary)
                            
                            Spacer()
                        }
//                        .offset(x: 0, y: max(0, (g.globalMinY - 100) * -proportion))
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
            
            // Buttons
            HStack(spacing: 10) {
                CodeButton(
                    style: .filledMedium,
                    title: "Add Cash",
                    action: presentOnramp
                )
                
                CodeButton(
                    style: .filledMediumSecondary,
                    title: "Withdraw"
                ) {
                    isShowingWithdrawFlow.toggle()
                }
                .sheet(isPresented: $isShowingWithdrawFlow) {
                    WithdrawDescriptionScreen(
                        isPresented: $isShowingWithdrawFlow,
                        container: container,
                        sessionContainer: sessionContainer
                    )
                }
            }
            .padding(.bottom, 30)
            .padding(.horizontal, 20)
        }
    }
    
//    @ViewBuilder private func row(activity: Activity) -> some View {
//        Button {
//            if BetaFlags.shared.hasEnabled(.transactionDetails) {
//                selectedActivity = activity
//            } else {
//                rowAction(activity: activity)
//            }
//        } label: {
//            VStack {
//                HStack {
//                    Text(activity.title)
//                        .font(.appTextMedium)
//                        .foregroundStyle(Color.textMain)
//                    Spacer()
//                    AmountText(
//                        flagStyle: activity.exchangedFiat.converted.currencyCode.flagStyle,
//                        flagSize: .small,
//                        content: activity.exchangedFiat.converted.formatted()
//                    )
//                    .font(.appTextMedium)
//                    .foregroundStyle(Color.textMain)
//                }
//                
//                HStack {
//                    Text(activity.date.formattedRelatively(useTimeForToday: true))
//                        .font(.appTextSmall)
//                        .foregroundStyle(Color.textSecondary)
//                    Spacer()
////                    if activity.exchangedFiat.converted.currencyCode != .usd {
////                        Text(activity.exchangedFiat.usdc.formatted()
////                            .font(.appTextSmall)
////                            .foregroundStyle(Color.textSecondary)
////                    }
//                }
//            }
//        }
//        .listRowBackground(Color.clear)
//        .padding(.horizontal, 20)
//        .padding(.vertical, 20)
//    }
    
    // MARK: - Action -
    
    private func presentOnramp() {
        onrampViewModel.presentRoot()
        Analytics.onrampOpenedFromBalance()
    }
    
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

// MARK: - GeometryProxy -

//extension GeometryProxy {
//    var globalMinY: CGFloat {
//        frame(in: .global).minY
//    }
//    
//    var globalHeight: CGFloat {
//        frame(in: .global).height
//    }
//}

// MARK: - AggregateBalance -

//struct AggregateBalance {
//    
//    let totalBalance: ExchangedFiat
//    let totalEntry: ExchangedFiat
//    
//    let entryRate: Rate
//    let balanceRate: Rate
//    
//    let entryBalances: [ExchangedBalance]
//    let balanceBalances: [ExchangedBalance]
//    
//    init(entryRate: Rate, balanceRate: Rate, balances: [StoredBalance]) {
//        self.entryRate   = entryRate
//        self.balanceRate = balanceRate
//        
//        var entryBalances: [ExchangedBalance]   = []
//        var balanceBalances: [ExchangedBalance] = []
//        
//        var totalUSDC: Fiat = .zero(currencyCode: .usd, decimals: PublicKey.usdc.mintDecimals)
//        
//        balances.sorted { lhs, rhs in
//            lhs.usdcValue.quarks > rhs.usdcValue.quarks
//        }.forEach { balance in
//            entryBalances.append(
//                ExchangedBalance(
//                    stored: balance,
//                    exchangedFiat: .computeFromQuarks(
//                        quarks: balance.quarks,
//                        mint: balance.mint,
//                        rate: entryRate,
//                        tvl: balance.coreMintLocked
//                    )
//                )
//            )
//            
//            balanceBalances.append(
//                ExchangedBalance(
//                    stored: balance,
//                    exchangedFiat: .computeFromQuarks(
//                        quarks: balance.quarks,
//                        mint: balance.mint,
//                        rate: balanceRate,
//                        tvl: balance.coreMintLocked
//                    )
//                )
//            )
//            
//            totalUSDC = try! totalUSDC.adding(balance.usdcValue)
//        }
//        
//        self.entryBalances   = entryBalances
//        self.balanceBalances = balanceBalances
//        
//        self.totalBalance = try! .init(
//            underlying: totalUSDC,
//            rate: balanceRate,
//            mint: .usdc
//        )
//        
//        self.totalEntry = try! .init(
//            underlying: totalUSDC,
//            rate: entryRate,
//            mint: .usdc
//        )
//    }
//    
//    func entryBalance(for mint: PublicKey) -> ExchangedBalance? {
//        entryBalances.first {
//            $0.stored.mint == mint
//        }
//    }
//    
//    func balanceBalance(for mint: PublicKey) -> ExchangedBalance? {
//        balanceBalances.first {
//            $0.stored.mint == mint
//        }
//    }
//}

struct ExchangedBalance: Identifiable, Hashable {
    let stored: StoredBalance
    let exchangedFiat: ExchangedFiat
    
    var id: PublicKey {
        stored.id
    }
}
