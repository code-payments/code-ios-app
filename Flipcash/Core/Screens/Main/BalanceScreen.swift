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
    
    @EnvironmentObject var session: Session
    @EnvironmentObject var ratesController: RatesController
    @EnvironmentObject var historyController: HistoryController
    
    @State private var isShowingCurrencySelection: Bool = false
    @State private var isShowingDepositScreen: Bool = false
    @State private var isShowingAddCashScreen: Bool = false
    @State private var isShowingWithdrawFlow: Bool = false
    
    @State private var dialogItem: DialogItem?
    
    @State private var selectedActivity: Activity?
    
    @StateObject private var updateableActivities: Updateable<[Activity]>
    
    private var activities: [Activity] {
        updateableActivities.value
    }
    
    private var hasActivities: Bool {
        !activities.isEmpty
    }
    
    private let proportion: CGFloat = 0.3
    
    private var balance: ExchangedFiat {
        session.exchangedBalance
    }
    
    private var isBalanceBaseCurrency: Bool {
        balance.converted.currencyCode == .usd
    }
    
    private let container: Container
    private let sessionContainer: SessionContainer
    private let database: Database
    
    // MARK: - Init -
    
    init(isPresented: Binding<Bool>, container: Container, sessionContainer: SessionContainer) {
        self._isPresented     = isPresented
        let database          = sessionContainer.database
        self.container        = container
        self.sessionContainer = sessionContainer
        self.database         = database
        
        self._updateableActivities = .init(wrappedValue: Updateable {
            (try? database.getActivities()) ?? []
        })
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
                .navigationTitle("Balance")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ToolbarCloseButton(binding: $isPresented)
                    }
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
            .navigationDestination(isPresented: $isShowingDepositScreen) {
                DepositDescriptionScreen(session: session)
            }
        }
        .dialog(item: $dialogItem)
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
        .frame(height: geometry.globalHeight * (1 - proportion - 0.1))
        .listRowBackground(Color.clear)
        .padding(.horizontal, 20)
    }
    
    @ViewBuilder private func list() -> some View {
        GeometryReader { g in
            List {
                Section {
                    if hasActivities {
                        ForEach(activities) { activity in
                            row(activity: activity)
                        }
                    } else {
                        emptyState(geometry: g)
                    }
                    
                } header: {
                    header(geometry: g)
                        .textCase(.none)
                }
                //.listSectionSeparator(.hidden)
                .listRowInsets(EdgeInsets())
                .listRowSeparatorTint(hasActivities ? .rowSeparator : .clear)
            }
            .listStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }
    
    @ViewBuilder private func header(geometry: GeometryProxy) -> some View {
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
                                content: balance.converted.formatted(suffix: nil),
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
                        .offset(x: 0, y: max(0, (g.globalMinY - 100) * -proportion))
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
                    title: "Add Cash"
                ) {
                    if BetaFlags.shared.hasEnabled(.enableCoinbase) || session.hasCoinbaseOnramp {
                        isShowingAddCashScreen = true
                    } else {
                        isShowingDepositScreen = true
                    }
                }
                .sheet(isPresented: $isShowingAddCashScreen) {
                    AddCashScreen(
                        isPresented: $isShowingAddCashScreen,
                        container: container,
                        sessionContainer: sessionContainer
                    )
                }
                
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
            .padding(.bottom, 10)
            .padding(.horizontal, 20)
        }
        .frame(height: geometry.globalHeight * proportion)
    }
    
    @ViewBuilder private func row(activity: Activity) -> some View {
        Button {
            if BetaFlags.shared.hasEnabled(.transactionDetails) {
                selectedActivity = activity
            } else {
                rowAction(activity: activity)
            }
        } label: {
            VStack {
                HStack {
                    Text(activity.title)
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                    Spacer()
                    AmountText(
                        flagStyle: activity.exchangedFiat.converted.currencyCode.flagStyle,
                        flagSize: .small,
                        content: activity.exchangedFiat.converted.formatted(suffix: nil)
                    )
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
                }
                
                HStack {
                    Text(activity.date.formattedRelatively(useTimeForToday: true))
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
//                    if activity.exchangedFiat.converted.currencyCode != .usd {
//                        Text(activity.exchangedFiat.usdc.formatted(suffix: " USD"))
//                            .font(.appTextSmall)
//                            .foregroundStyle(Color.textSecondary)
//                    }
                }
            }
        }
        .listRowBackground(Color.clear)
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
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
            title: "Cancel \(activity.exchangedFiat.converted.formatted(suffix: nil)) Transfer?",
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

extension GeometryProxy {
    var globalMinY: CGFloat {
        frame(in: .global).minY
    }
    
    var globalHeight: CGFloat {
        frame(in: .global).height
    }
}
