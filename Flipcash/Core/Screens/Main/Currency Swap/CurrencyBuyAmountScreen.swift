//
//  CurrencyBuyAmountScreen.swift
//  Code
//
//  Created by Raul Riera on 2025-12-18.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct CurrencyBuyAmountScreen: View {
    @ObservedObject private var viewModel: CurrencyBuyViewModel
    @Environment(\.dismiss) var dismissAction: DismissAction
    @EnvironmentObject private var ratesController: RatesController
    
    @State private var isShowingCurrencySelection: Bool = false
        
    // MARK: - Init -
    
    init(viewModel: CurrencyBuyViewModel) {
        self.viewModel = viewModel
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            EnterAmountView(
                mode: .buy,
                enteredAmount: $viewModel.enteredAmount,
                subtitle: .balanceWithLimit(viewModel.maxPossibleAmount),
                actionState: $viewModel.actionButtonState,
                actionEnabled: { _ in
                    viewModel.canPerformAction
                },
                action: viewModel.amountEnteredAction,
                currencySelectionAction: showCurrencySelection
            )
            .foregroundColor(.textMain)
            .padding(20)
        }
        .navigationTitle(viewModel.screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .dialog(item: $viewModel.dialogItem)
        .onDisappear {
            viewModel.reset()
        }
        .onChange(of: viewModel.actionButtonState) { _, newValue in
            guard newValue == .success else { return }
            dismissAction()
        }
        .sheet(isPresented: $isShowingCurrencySelection) {
            CurrencySelectionScreen(
                isPresented: $isShowingCurrencySelection,
                kind: .entry,
                ratesController: ratesController
            )
        }
    }
    
    private func showCurrencySelection() {
        isShowingCurrencySelection.toggle()
    }
}
