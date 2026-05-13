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
    @Environment(OnrampCoordinator.self) private var coordinator
    @Environment(RatesController.self) private var ratesController
    @Environment(WalletConnection.self) private var walletConnection
    @Environment(Session.self) private var session

    init(mint: PublicKey, currencyName: String, session: Session, ratesController: RatesController) {
        self._viewModel = State(initialValue: BuyAmountViewModel(
            mint: mint,
            currencyName: currencyName,
            session: session,
            ratesController: ratesController
        ))
    }

    private var isDismissBlocked: Bool {
        coordinator.isProcessingPayment || walletConnection.isAwaitingExternalSwap
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
        .toolbar {
            if !isDismissBlocked {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton(action: router.dismissSheet)
                }
            }
        }
        .navigationDestination(for: BuyFlowPath.self) { path in
            // Env value must be set on the destination view itself — modifiers
            // on the source view don't propagate to navigation destinations
            // (they live in a separate SwiftUI context).
            //
            // SwapProcessingScreen at the leaf observes
            // `walletConnection.isProcessingCancelled` for failure flips, so
            // clearing the wallet state happens on OK (here), not at push
            // time. For Coinbase and direct-USDF paths walletConnection state
            // is already idle, so `dismissProcessing()` is a no-op.
            BuyFlowDestinationView(path: path)
                .environment(\.dismissParentContainer, {
                    walletConnection.dismissProcessing()
                    router.dismissSheet()
                })
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
        // Forward wallet-connection dialogs (Phantom cancel during signing,
        // simulate failures, etc.) to `session.dialogItem` so they render in
        // `DialogWindow` at alert level instead of trying to mount a sheet
        // on `CurrencyInfoScreen` — which fights the `.buy` sheet's
        // presentation queue and dismisses it.
        // `DialogItem` isn't Equatable, so observe the id (UUID) and read the
        // current value in the handler.
        .onChange(of: walletConnection.dialogItem?.id) { _, newId in
            guard newId != nil, let dialog = walletConnection.dialogItem else { return }
            session.dialogItem = dialog
            walletConnection.dialogItem = nil
        }
        // The Phantom processing push is owned by `PhantomConfirmScreen` —
        // observing `walletConnection.processing` here too would double-push
        // when both screens are alive (PhantomConfirm still on top during the
        // state transition).
    }

    private func showCurrencySelection() {
        isShowingCurrencySelection.toggle()
    }
}
