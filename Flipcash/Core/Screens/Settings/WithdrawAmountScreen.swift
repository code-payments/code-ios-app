//
//  WithdrawAmountScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-04-17.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct WithdrawAmountScreen: View {
    
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var ratesController: RatesController
    
    @ObservedObject private var viewModel: WithdrawViewModel
    
    @State private var isShowingCurrencySelection: Bool = false
    
    // MARK: - Init -
    
    init(viewModel: WithdrawViewModel) {
        self.viewModel = viewModel
    }
    
    // MARK: - Body -
    
    #warning("Add support for max withdrawal")
    var body: some View {
        Background(color: .backgroundMain) {
            EnterAmountView(
                mode: .withdraw,
                enteredAmount: $viewModel.enteredAmount,
                subtitle: .balanceWithLimit(viewModel.maxWithdrawLimit),
                actionState: .constant(.normal),
                actionEnabled: { _ in
                    viewModel.enteredFiat != nil
                },
                action: viewModel.amountEnteredAction,
                currencySelectionAction: nil
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
        }
        .navigationTitle(viewModel.withdrawTitle)
        .navigationBarTitleDisplayMode(.inline)
        .dialog(item: $viewModel.dialogItem)
    }
    
    // MARK: - Actions -
    
    private func showCurrencySelection() {
        isShowingCurrencySelection.toggle()
    }
}
