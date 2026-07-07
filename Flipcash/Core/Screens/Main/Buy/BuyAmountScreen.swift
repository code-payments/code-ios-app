//
//  BuyAmountScreen.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-05-12.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

struct BuyAmountScreen: View {

    @State private var viewModel: BuyAmountViewModel
    @State private var isShowingCurrencySelection: Bool = false

    @Environment(AppRouter.self) private var router
    @Environment(RatesController.self) private var ratesController

    init(mint: PublicKey, currencyName: String, session: Session, ratesController: RatesController) {
        self._viewModel = State(initialValue: BuyAmountViewModel(
            mint: mint,
            currencyName: currencyName,
            session: session,
            ratesController: ratesController
        ))
    }

    private var isDismissBlocked: Bool {
        // Any pushed sub-flow screen (processing) — destination-level
        // `interactiveDismissDisabled(true)` does NOT propagate through the
        // nested-sheet binding, so gate at the NavigationStack root by
        // checking the path is non-empty.
        !router[.buy].isEmpty
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        Background(color: .backgroundMain) {
            EnterAmountView(
                mode: .buy,
                enteredAmount: $viewModel.enteredAmount,
                subtitle: .singleTransactionLimit,
                actionState: $viewModel.actionButtonState,
                actionEnabled: { _ in viewModel.canPerformAction },
                action: {
                    Task { await viewModel.amountEnteredAction(router: router) }
                },
                currencySelectionAction: showCurrencySelection
            )
            .foregroundStyle(.textMain)
            .padding(20)
        }
        .ignoresSafeArea(.keyboard)
        .navigationTitle(viewModel.screenTitle)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            if !isDismissBlocked {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton(action: router.dismissSheet)
                }
            }
        }
        .interactiveDismissDisabled(isDismissBlocked)
        .navigationDestination(for: BuyFlowPath.self) { path in
            // Env value must be set on the destination view itself — modifiers
            // on the source view don't propagate to navigation destinations
            // (they live in a separate SwiftUI context).
            BuyFlowDestinationView(path: path)
                .environment(\.dismissParentContainer, router.dismissSheet)
        }
        .dialog(item: $viewModel.dialogItem)
        .sheet(isPresented: $isShowingCurrencySelection) {
            CurrencySelectionScreen(ratesController: ratesController)
        }
    }

    private func showCurrencySelection() {
        isShowingCurrencySelection.toggle()
    }
}
