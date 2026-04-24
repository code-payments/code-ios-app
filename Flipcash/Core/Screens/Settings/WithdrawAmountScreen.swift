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
    
    @Environment(Session.self) private var session
    @Environment(RatesController.self) private var ratesController
    
    @Bindable private var viewModel: WithdrawViewModel
    
    @State private var isShowingCurrencySelection: Bool = false
    
    // MARK: - Init -
    
    init(viewModel: WithdrawViewModel) {
        self.viewModel = viewModel
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            EnterAmountView(
                mode: .withdraw,
                enteredAmount: $viewModel.enteredAmount,
                subtitle: viewModel.subtitle,
                actionState: .constant(.normal),
                actionEnabled: { _ in
                    viewModel.canProceedToAddress
                },
                action: viewModel.amountEnteredAction,
                currencySelectionAction: showCurrencySelection
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
        .onChange(of: ratesController.entryCurrency) { _, _ in
            // Pin is captured for a specific (currency, mint); re-fetch so
            // the amount screen reflects the switched currency instead of
            // silently continuing on the old one.
            viewModel.rePinForEntryCurrency()
        }
    }
    
    // MARK: - Actions -
    
    private func showCurrencySelection() {
        isShowingCurrencySelection.toggle()
    }
}
