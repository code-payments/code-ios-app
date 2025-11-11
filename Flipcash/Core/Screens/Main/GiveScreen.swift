//
//  GiveScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-04-17.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct GiveScreen: View {
    
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var ratesController: RatesController
    
    @ObservedObject private var onrampViewModel: OnrampViewModel
    @ObservedObject private var viewModel: GiveViewModel
    
    @State private var isShowingCurrencySelection: Bool = false
    
    @State private var dialogItem: DialogItem?
    
    private var maxLimit: ExchangedFiat {
        let entryRate = ratesController.rateForEntryCurrency()
        let zero      = try! ExchangedFiat(usdc: 0, rate: entryRate, mint: .usdc)
        
        guard let mint = viewModel.selectedBalance?.stored.mint else {
            return zero
        }
        
        guard let balance = session.balance(for: mint) else {
            return zero
        }
        
        return balance.computeExchangedValue(with: entryRate)
    }
    
    // MARK: - Init -
    
    init(viewModel: GiveViewModel) {
        self.viewModel       = viewModel
        self.onrampViewModel = viewModel.sessionContainer.onrampViewModel
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            EnterAmountView(
                mode: .currency,
                enteredAmount: $viewModel.enteredAmount,
                subtitle: .balanceWithLimit(maxLimit),
                actionState: $viewModel.actionState,
                actionEnabled: { _ in
                    viewModel.canGive
                },
                action: nextAction,
                currencySelectionAction: showCurrencySelection
            )
            .foregroundColor(.textMain)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .padding(.top, -20)
            .sheet(isPresented: $isShowingCurrencySelection) {
                CurrencySelectionScreen(
                    isPresented: $isShowingCurrencySelection,
                    kind: .entry,
                    ratesController: ratesController
                )
            }
        }
        .ignoresSafeArea(.keyboard)
        .navigationTitle("Enter Amount")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $onrampViewModel.isMethodSelectionPresented) {
            AddCashScreen(
                isPresented: $onrampViewModel.isMethodSelectionPresented,
                container: viewModel.container,
                sessionContainer: viewModel.sessionContainer
            )
        }
        .sheet(isPresented: $onrampViewModel.isOnrampPresented) {
            PartialSheet(background: .backgroundMain) {
                PresetAddCashScreen(
                    isPresented: $onrampViewModel.isOnrampPresented,
                    container: viewModel.container,
                    sessionContainer: viewModel.sessionContainer
                )
            }
        }
        .dialog(item: $dialogItem)
        .dialog(item: $onrampViewModel.purchaseSuccess)
        .dialog(item: $viewModel.dialogItem)
    }
    
    // MARK: - Actions -
    
    private func nextAction() {
        viewModel.giveAction()
    }
    
    private func showCurrencySelection() {
        isShowingCurrencySelection.toggle()
    }
}
