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
    @Environment(PhantomCoordinator.self) private var phantomCoordinator
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
        // Any pushed sub-flow screen (Phantom confirm, USDC deposit address,
        // processing) — destination-level `interactiveDismissDisabled(true)`
        // does NOT propagate through the nested-sheet binding, so gate at
        // the NavigationStack root by checking the path is non-empty.
        if !router[.buy].isEmpty { return true }
        return coordinator.isProcessingPayment || phantomCoordinator.isAwaitingExternalSwap
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        @Bindable var coordinator = coordinator
        Background(color: .backgroundMain) {
            EnterAmountView(
                mode: .buy,
                enteredAmount: $viewModel.enteredAmount,
                subtitle: .singleTransactionLimit,
                // Surface coordinator's in-flight Apple Pay/Coinbase setup as
                // a spinner on the Buy button — the picker dismisses fast and
                // the Apple Pay sheet can take a beat to open.
                actionState: Binding(
                    get: { coordinator.isProcessingPayment ? .loading : viewModel.actionButtonState },
                    set: { viewModel.actionButtonState = $0 }
                ),
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
        .interactiveDismissDisabled(isDismissBlocked)
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
                    phantomCoordinator.dismissProcessing()
                    router.dismissSheet()
                })
        }
        .dialog(item: $viewModel.dialogItem)
        // Coordinator surfaces Coinbase/Apple Pay failures (e.g. order
        // creation rejected, swap-amount mismatch) via its own dialog item;
        // bind it here so the user sees the error instead of a silent flicker.
        .dialog(item: $coordinator.dialogItem)
        .sheet(item: $viewModel.pendingOperation) { operation in
            PurchaseMethodSheet(
                operation: operation,
                sources: [.applePay, .phantom, .otherWallet],
                applePayAction: nil,
                onDismiss: { viewModel.pendingOperation = nil }
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
        // Phantom-funded buy: when the signed tx returns and the coordinator
        // transitions to .buying(...), push the processing screen onto the
        // `.buy` stack. Gated on nil → non-nil so we don't double-push when
        // the server callback reassigns the buying context to a new swap id.
        .onChange(of: phantomCoordinator.processing) { oldValue, newValue in
            guard oldValue == nil, let newValue else { return }
            router.pushAny(BuyFlowPath.processing(
                swapId: newValue.swapId,
                currencyName: newValue.currencyName,
                amount: newValue.amount,
                swapType: .buyWithPhantom
            ))
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
            // Defer the clear past the current observation tick so we don't
            // mutate the observed value in the same update cycle that fired
            // this handler.
            Task { @MainActor in
                walletConnection.dialogItem = nil
            }
        }
    }

    private func showCurrencySelection() {
        isShowingCurrencySelection.toggle()
    }
}
