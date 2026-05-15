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
        // Any pushed sub-flow screen (Phantom confirm, USDC deposit address,
        // processing) — destination-level `interactiveDismissDisabled(true)`
        // does NOT propagate through the nested-sheet binding, so gate at
        // the NavigationStack root by checking the path is non-empty.
        if !router[.buy].isEmpty { return true }
        if coordinator.isProcessingPayment { return true }
        return isPhantomMidFlight
    }

    /// True while the Phantom funding operation is past the picker — the
    /// user has tapped Phantom and we either hit the wallet, are signing,
    /// or are running the post-sign chain step.
    private var isPhantomMidFlight: Bool {
        switch viewModel.fundingOperation?.state {
        case .awaitingExternal, .working: return true
        default: return false
        }
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
            BuyFlowDestinationView(path: path)
                .environment(\.dismissParentContainer, router.dismissSheet)
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
                phantomAction: { payment in
                    viewModel.startPhantomFunding(
                        payment: payment,
                        walletConnection: walletConnection,
                        router: router
                    )
                },
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
        .fundingFlowHost(viewModel.fundingOperation)
    }

    private func showCurrencySelection() {
        isShowingCurrencySelection.toggle()
    }
}
