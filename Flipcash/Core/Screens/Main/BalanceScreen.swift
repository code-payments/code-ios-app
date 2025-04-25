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
    
    private var activities: [Activity] {
        historyController.activities
    }
    
    private let proportion: CGFloat = 0.3
    
    private var convertedFiat: Fiat {
        session.exchangedBalance.converted
    }
    
    // MARK: - Init -
    
    init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
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
        }
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
                        
                        if convertedFiat.currencyCode != .usd {
                            Text("Your balance is held in US dollars")
                                .font(.appTextSmall)
                                .foregroundStyle(Color.textSecondary)
                        }
                        
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
        .listRowBackground(Color.clear)
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
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

// MARK: - Preview -

#Preview {
    BalanceScreen(isPresented: .constant(true))
}
