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
                    if let amount = viewModel.enteredFiat {
                        CurrencySellConfirmationScreen(
                            mint: viewModel.currencyMetadata.mint,
                            currencyName: viewModel.currencyMetadata.name,
                            amount: amount,
                            pinnedState: viewModel.pinnedState,
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
            .onChange(of: ratesController.entryCurrency) { _, newCurrency in
                // Pin is captured at flow open for a specific currency; re-fetch
                // here so the amount screen reflects the switched currency.
                // Guard on assignment so a slow fetch for a no-longer-selected
                // currency can't clobber a newer pick.
                Task {
                    guard newCurrency != viewModel.pinnedState.currencyCode,
                          let newPin = await ratesController.currentPinnedState(for: newCurrency, mint: viewModel.currencyMetadata.mint),
                          ratesController.entryCurrency == newCurrency
                    else { return }
                    viewModel.pinnedState = newPin
                }
            }
        }
    }
    
    private func showCurrencySelection() {
        isShowingCurrencySelection.toggle()
    }
}
