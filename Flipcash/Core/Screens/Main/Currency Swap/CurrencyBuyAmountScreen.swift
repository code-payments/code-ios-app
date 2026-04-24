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
    @Bindable private var viewModel: CurrencyBuyViewModel
    @Environment(\.dismiss) var dismissAction: DismissAction
    @Environment(RatesController.self) private var ratesController

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
                case .processing(let swapId, let currencyName, let amount):
                    SwapProcessingScreen(swapId: swapId, swapType: .buyWithReserves, currencyName: currencyName, amount: amount)
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
            .onChange(of: ratesController.entryCurrency) { _, newCurrency in
                // The pin is captured for a specific currency at flow open;
                // without this hook the display would stay on the old
                // currency's math after the user switches. Guard on
                // assignment so a slow fetch for a no-longer-selected
                // currency can't clobber a newer pick.
                Task {
                    guard newCurrency != viewModel.pinnedState.currencyCode,
                          let newPin = await ratesController.currentPinnedState(for: newCurrency, mint: .usdf),
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
