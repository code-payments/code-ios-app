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
    @ObservedObject private var viewModel: CurrencySellViewModel
    @Environment(\.dismiss) var dismissAction: DismissAction
    @EnvironmentObject private var ratesController: RatesController
    
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
                    mode: .currency,
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
                    if let amount = viewModel.enteredFiat {
                        CurrencySellConfirmationScreen(mint: viewModel.currencyMetadata.mint, amount: amount)
                            .environment(\.dismissParentContainer, {
                                dismissAction()
                                // FIXME: Flows like these and Withdraw keep a reference to the view models in the parent
                                // forcing to clear them when dismissed
                                viewModel.reset()
                            })
                    }
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
