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
    
    @ObservedObject private var viewModel: OnrampViewModel
    
    // MARK: - Init -
    
    init(viewModel: OnrampViewModel) {
        self.viewModel = viewModel
    }
    
    // MARK: - Body -
    
    var body: some View {
        NavigationStack {
            Background(color: .backgroundMain) {
                EnterAmountView(
                    mode: .onramp,
                    enteredAmount: $viewModel.enteredAmount,
                    subtitle: .singleTransactionLimit,
                    actionState: $viewModel.payButtonState,
                    actionEnabled: { _ in
                        viewModel.enteredFiat != nil
                    },
                    action: viewModel.customAmountEnteredAction,
                    currencySelectionAction: nil,
                )
                .foregroundColor(.textMain)
                .padding(20)
                .overlay {
                    viewModel.applePayWebView()
                }
            }
            .navigationTitle("Amount to Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarCloseButton(binding: $viewModel.isShowingAmountEntryScreen)
                }
            }
        }
        .dialog(item: $viewModel.dialogItem)
    }
}
