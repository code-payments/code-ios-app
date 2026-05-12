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

    @Environment(AppRouter.self) private var router

    init(mint: PublicKey, currencyName: String, session: Session, ratesController: RatesController) {
        self._viewModel = State(initialValue: BuyAmountViewModel(
            mint: mint,
            currencyName: currencyName,
            session: session,
            ratesController: ratesController
        ))
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
                }
            )
            .foregroundStyle(.textMain)
            .padding(20)
        }
        .navigationTitle(viewModel.screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .dialog(item: $viewModel.dialogItem)
        .sheet(item: $viewModel.pendingMethodSelection) { context in
            PurchaseMethodSheet(
                context: context,
                onDismiss: { viewModel.pendingMethodSelection = nil }
            )
        }
    }
}
