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
    
    @State private var dialogItem: DialogItem?
    
    @StateObject private var updateableActivities: Updateable<[Activity]>
    
    private var activities: [Activity] {
        updateableActivities.value
    }
    
    private let proportion: CGFloat = 0.3
    
    private var convertedFiat: Fiat {
        session.exchangedBalance.converted
    }
    
    private let database: Database
    
    // MARK: - Init -
    
    init(isPresented: Binding<Bool>, container: Container, database: Database) {
        self._isPresented = isPresented
        let database      = database
        self.database     = database
        
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
                    GeometryReader { g in
                        List {
                            Section {
                                ForEach(activities) { activity in
                                    row(activity: activity)
                                }
                                
                            } header: {
                                header(geometry: g)
                                    .textCase(.none)
                            }
//                            .listSectionSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparatorTint(Color.rowSeparator)
                        }
                        .listStyle(.grouped)
                        .scrollContentBackground(.hidden)
                    }
                }
                .navigationTitle("Balance")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ToolbarCloseButton(binding: $isPresented)
                    }
                }
            }
            .onAppear(perform: onAppear)
        }
        .dialog(item: $dialogItem)
    }
    
    @ViewBuilder private func header(geometry: GeometryProxy) -> some View {
        Button {
            isShowingCurrencySelection.toggle()
        } label: {
            VStack {
                GeometryReader { g in
                    VStack {
                        Spacer()
                        
                        AmountText(
                            flagStyle: convertedFiat.currencyCode.flagStyle,
                            content: convertedFiat.formattedWithSuffixIfNeeded(),
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
            .frame(height: geometry.globalHeight * proportion)
        }
        .sheet(isPresented: $isShowingCurrencySelection) {
            CurrencySelectionScreen(
                isPresented: $isShowingCurrencySelection,
                kind: .balance,
                ratesController: ratesController
            )
        }
    }
    
    @ViewBuilder private func row(activity: Activity) -> some View {
        Button {
            rowAction(activity: activity)
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
                    Text(activity.date.formattedRelatively())
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    if activity.exchangedFiat.converted.currencyCode != .usd {
                        Text(activity.exchangedFiat.usdc.formatted(suffix: " USD"))
                            .font(.appTextSmall)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
        .listRowBackground(Color.clear)
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }
    
    // MARK: - Action -
    
    private func rowAction(activity: Activity) {
        switch activity.state {
        case .pending:
            if case .cashLink(let cashLinkMetadata) = activity.metadata, cashLinkMetadata.canCancel {
                cancelCashLinkAction(
                    activity: activity,
                    metadata: cashLinkMetadata
                )
            }
            
        case .completed, .unknown:
            break
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
                
                // TODO: Move into Session?
                try? await historyController.syncPendingActivities()
                try? await session.fetchBalance()
                
            } catch {
                dialogItem = .init(
                    style: .destructive,
                    title: "Failed to Cancel Transfer",
                    subtitle: "Something went wrong. Please try again later",
                    dismissable: true
                ) {
                    .okay()
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
