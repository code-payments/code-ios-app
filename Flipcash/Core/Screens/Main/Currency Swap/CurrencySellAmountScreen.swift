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
                .foregroundStyle(.textMain)
                .padding(20)
            }
            .ignoresSafeArea(.keyboard)
            .navigationTitle(viewModel.screenTitle)
            .toolbarTitleDisplayMode(.inline)
            .navigationDestination(for: CurrencySellPath.self) { step in
                switch step {
                case .confirmation(let amount, let pinnedState):
                    CurrencySellConfirmationScreen(
                        mint: viewModel.currencyMetadata.mint,
                        currencyName: viewModel.currencyMetadata.name,
                        amount: amount,
                        pinnedState: pinnedState,
                        sellFeeBps: viewModel.currencyMetadata.sellFeeBps,
                        path: $viewModel.path
                    )
                    .environment(\.dismissParentContainer, {
                        dismissAction()
                    })
                case .processing(let swapId, let currencyName, let amount):
                    SwapProcessingScreen(swapId: swapId, swapType: .sell, currencyName: currencyName, amount: amount)
                        .environment(\.dismissParentContainer, {
                            dismissAction()
                        })
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton { dismissAction() }
                }
            }
            .dialog(item: $viewModel.dialogItem)
            .sheet(isPresented: $isShowingCurrencySelection) {
                CurrencySelectionScreen(ratesController: ratesController)
            }
        }
    }

    private func showCurrencySelection() {
        isShowingCurrencySelection.toggle()
    }
}
