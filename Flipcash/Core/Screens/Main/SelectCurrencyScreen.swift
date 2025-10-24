//
//  SelectCurrencyScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-10-17.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct SelectCurrencyScreen: View {
    
    @Binding var isPresented: Bool
    
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var ratesController: RatesController
    
    @StateObject private var viewModel: GiveViewModel
    
    @State private var selectedBalance: ExchangedBalance?
    
    private var aggregateBalance: AggregateBalance {
        AggregateBalance(
            entryRate: ratesController.rateForEntryCurrency(),
            balanceRate: ratesController.rateForBalanceCurrency(),
            balances: session.balances
        )
    }
    
    let container: Container
    let sessionContainer: SessionContainer
    
    private var entryRate: Rate {
        ratesController.rateForEntryCurrency()
    }
    
    // MARK: - Init -
    
    init(isPresented: Binding<Bool>, container: Container, sessionContainer: SessionContainer) {
        self._isPresented        = isPresented
        self.container           = container
        self.sessionContainer    = sessionContainer
        
        self._viewModel = .init(
            wrappedValue: GiveViewModel(
                isPresented: isPresented,
                container: container,
                sessionContainer: sessionContainer
            )
        )
    }
    
    // MARK: - Body -
    
    var body: some View {
        NavigationStack(path: $viewModel.navigationPath) {
            Background(color: .backgroundMain) {
                List {
                    Section {
                        ForEach(aggregateBalance.exchangedBalance(for: entryRate)) { balance in
                            CurrencyBalanceRow(exchangedBalance: balance) {
                                viewModel.selectCurrencyAction(exchangedBalance: balance)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets())
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Select Currency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarCloseButton(binding: $isPresented)
                }
            }
            .navigationDestination(for: GivePath.self) { path in
                switch path {
                case .giveScreen:
                    GiveScreen(viewModel: viewModel)
                }
            }
        }
    }
}

struct CurrencyBalanceRow: View {
    
    let exchangedBalance: ExchangedBalance
    let action: (() -> Void)?
    
    init(exchangedBalance: ExchangedBalance, action: (() -> Void)? = nil) {
        self.exchangedBalance = exchangedBalance
        self.action = action
    }
    
    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 8) {
                if let imageURL = exchangedBalance.stored.imageURL {
                    RemoteImage(url: imageURL)
                        .frame(width: 24, height: 24)
                        .clipShape(Circle())
                }
                
                Text(exchangedBalance.stored.name)
                    .font(.appBarButton)
                    .foregroundStyle(Color.textMain)
                
                Spacer()
                
                Text(exchangedBalance.exchangedFiat.converted.formatted(suffix: nil))
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
            }
        }
        .disabled(action == nil)
        .listRowBackground(Color.clear)
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }
}
