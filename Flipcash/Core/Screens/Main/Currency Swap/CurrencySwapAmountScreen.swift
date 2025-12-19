//
//  CurrencySwapAmountScreen.swift
//  Code
//
//  Created by Raul Riera on 2025-12-18.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct CurrencySwapAmountScreen: View {
    @ObservedObject private var viewModel: CurrencySwapViewModel
    @Environment(\.dismiss) var dismissAction: DismissAction
        
    // MARK: - Init -
    
    init(viewModel: CurrencySwapViewModel) {
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
                currencySelectionAction: nil
            )
            .foregroundColor(.textMain)
            .padding(20)
        }
        .navigationTitle(viewModel.screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .dialog(item: $viewModel.dialogItem)
        .onChange(of: viewModel.actionButtonState) { _, newValue in
            guard newValue == .success else { return }
            dismissAction()
        }
    }
}
