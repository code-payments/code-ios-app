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
        NavigationStack(path: $viewModel.path) {
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
            .navigationDestination(for: CurrencyBuyPath.self) { step in
                switch step {
                case .processing(let swapId, let mint, let amount):
                    SwapProcessingScreen(swapId: swapId, swapType: .buy, mint: mint, amount: amount)
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
            .dialog(item: $viewModel.dialogItem)
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
