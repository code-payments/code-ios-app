//
//  CurrencySellAmountScreen.swift
//  Code
//
//  Created by Raul Riera on 2025-12-30.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct CurrencySellAmountScreen: View {
    @Bindable private var viewModel: CurrencySellViewModel
    @Environment(\.dismiss) var dismissAction: DismissAction
    @Environment(RatesController.self) private var ratesController

    @State private var isShowingCurrencySelection: Bool = false

    // MARK: - Init -

    init(viewModel: CurrencySellViewModel) {
        self.viewModel = viewModel
    }
    
    // MARK: - Body -
    
    var body: some View {
        NavigationStack(path: $viewModel.path) {
            Background(color: .backgroundMain) {
                EnterAmountView(
                    mode: .sell,
                    enteredAmount: $viewModel.enteredAmount,
                    subtitle: .balanceWithLimit(viewModel.maxPossibleAmount),
                    actionState: .constant(.normal),
                    actionEnabled: { _ in
                        viewModel.canPerformAction
                    },
                    action: viewModel.showConfirmationScreen,
                    currencySelectionAction: showCurrencySelection
                )
                .foregroundColor(.textMain)
                .padding(20)
            }
            .navigationTitle(viewModel.screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: CurrencySellPath.self) { step in
                switch step {
                case .confirmation:
                    if let amount = viewModel.enteredFiat, let pinnedState = viewModel.pinnedState {
                        CurrencySellConfirmationScreen(
                            mint: viewModel.currencyMetadata.mint,
                            currencyName: viewModel.currencyMetadata.name,
                            amount: amount,
                            pinnedState: pinnedState,
                            path: $viewModel.path
                        )
                        .environment(\.dismissParentContainer, {
                            dismissAction()
                        })
                    }
                case .processing(let swapId, let currencyName, let amount):
                    SwapProcessingScreen(swapId: swapId, swapType: .sell, currencyName: currencyName, amount: amount)
                        .environment(\.dismissParentContainer, {
                            dismissAction()
                        })
                }
            }
            .toolbar {
                ToolbarCloseButton {
                    dismissAction()
                }
            }
            .sheet(isPresented: $isShowingCurrencySelection) {
                CurrencySelectionScreen(
                    isPresented: $isShowingCurrencySelection,
                    kind: .entry,
                    ratesController: ratesController
                )
            }
        }
    }
    
    private func showCurrencySelection() {
        isShowingCurrencySelection.toggle()
    }
}
