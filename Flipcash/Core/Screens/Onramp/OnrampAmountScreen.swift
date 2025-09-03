//
//  OnrampAmountScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-04-17.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct OnrampAmountScreen: View {
    
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var ratesController: RatesController
    
    @ObservedObject private var viewModel: OnrampViewModel
    
    @State private var isShowingCurrencySelection: Bool = false
    
    // MARK: - Init -
    
    init(viewModel: OnrampViewModel) {
        self.viewModel = viewModel
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            EnterAmountView(
                mode: .onramp,
                enteredAmount: $viewModel.enteredAmount,
                subtitle: .singleTransactionLimit,
                actionState: $viewModel.payButtonState,
                actionEnabled: { _ in
                    viewModel.enteredFiat != nil
                },
                action: viewModel.amountEnteredAction,
                currencySelectionAction: nil,//showCurrencySelection
            )
            .foregroundColor(.textMain)
            .padding(20)
            .sheet(isPresented: $isShowingCurrencySelection) {
                CurrencySelectionScreen(
                    isPresented: $isShowingCurrencySelection,
                    kind: .entry,
                    ratesController: ratesController
                )
            }
            .overlay {
                viewModel.applePayWebView()
            }
        }
        .navigationTitle("Amount to Add")
        .navigationBarTitleDisplayMode(.inline)
        .dialog(item: $viewModel.dialogItem)
    }
    
    // MARK: - Actions -
    
//    private func showCurrencySelection() {
//        isShowingCurrencySelection.toggle()
//    }
}
