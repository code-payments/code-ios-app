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
    /// Path depth on the balance stack at the entry to the buy flow. Captured
    /// on first appear so the buy flow can pop back to whatever pushed it
    /// (typically `currencyInfo`) when the user completes or cancels, without
    /// knowing how many sub-flow screens were pushed in between.
    @State private var parentDepth: Int?

    @Environment(AppRouter.self) private var router
    @Environment(OnrampCoordinator.self) private var coordinator
    @Environment(RatesController.self) private var ratesController

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
        @Bindable var coordinator = coordinator
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
        .navigationTitle(viewModel.screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: BuyFlowPath.self) { path in
            // Env value must be set on the destination view itself — modifiers
            // on the source view don't propagate to navigation destinations
            // (they live in a separate SwiftUI context).
            BuyFlowDestinationView(path: path)
                .environment(\.dismissParentContainer, dismissBuyFlow)
        }
        .dialog(item: $viewModel.dialogItem)
        .sheet(item: $viewModel.pendingMethodSelection) { context in
            PurchaseMethodSheet(
                context: context,
                onDismiss: { viewModel.pendingMethodSelection = nil }
            )
        }
        .sheet(isPresented: $coordinator.isShowingVerificationFlow) {
            VerifyInfoScreen(onrampCoordinator: coordinator)
        }
        .sheet(isPresented: $isShowingCurrencySelection) {
            CurrencySelectionScreen(ratesController: ratesController)
        }
        .onChange(of: coordinator.completion) { _, newValue in
            guard case .buyProcessing(let swapId, let currencyName, let amount) = newValue else { return }
            router.pushAny(BuyFlowPath.processing(
                swapId: swapId,
                currencyName: currencyName,
                amount: amount,
                swapType: .buyWithCoinbase
            ))
            coordinator.completion = nil
        }
        .onAppear {
            if parentDepth == nil {
                // path.count includes this view's own push (we're already on
                // the stack when onAppear fires). Subtract 1 to get the depth
                // of the screen that triggered the buy — what we pop back to
                // when the user finishes the flow.
                parentDepth = max(0, router[.balance].count - 1)
            }
        }
    }

    private func showCurrencySelection() {
        isShowingCurrencySelection.toggle()
    }

    /// Pops every screen pushed since the buy flow started — `buyAmount`
    /// itself plus any sub-flow (`phantomEducation`, `phantomConfirm`,
    /// `usdcDepositEducation`, `usdcDepositAddress`, `processing`). Used by
    /// `SwapProcessingScreen`'s OK button via `dismissParentContainer`.
    private var dismissBuyFlow: () -> Void {
        let depth = parentDepth
        return { [router] in
            guard let depth else { return }
            let toPop = router[.balance].count - depth
            guard toPop > 0 else { return }
            router.popLast(toPop, on: .balance)
        }
    }
}
