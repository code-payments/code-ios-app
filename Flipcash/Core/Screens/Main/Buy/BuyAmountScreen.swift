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
    /// Identity of the Phantom operation we've already pushed `.phantomFlow`
    /// for. Reset when the operation slot empties so a retry pushes again.
    @State private var phantomFlowPushedFor: ObjectIdentifier?

    @Environment(AppRouter.self) private var router
    @Environment(OnrampCoordinator.self) private var coordinator
    @Environment(CoinbaseService.self) private var coinbaseService
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
        // Any pushed sub-flow screen (Phantom flow, USDC deposit address,
        // processing) — destination-level `interactiveDismissDisabled(true)`
        // does NOT propagate through the nested-sheet binding, so gate at
        // the NavigationStack root by checking the path is non-empty.
        if !router[.buy].isEmpty { return true }
        if coordinator.isProcessingPayment { return true }
        if coinbaseService.coinbaseOrder != nil { return true }
        return isFundingMidFlight
    }

    /// True while a funding operation (Phantom or Coinbase) is past the
    /// picker — user is in the wallet, the Apple Pay sheet, or we're
    /// running a chain step.
    private var isFundingMidFlight: Bool {
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
                // Surface an in-flight funding operation (Coinbase order
                // creation, Apple Pay sheet warm-up, Phantom handshake /
                // sign / chain submit) as a spinner on the Buy button —
                // the picker dismisses fast and the Apple Pay overlay can
                // take ~5s to mount.
                actionState: Binding(
                    get: {
                        if coordinator.isProcessingPayment { return .loading }
                        if isFundingMidFlight { return .loading }
                        return viewModel.actionButtonState
                    },
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
                applePayAction: { payment in
                    viewModel.startCoinbaseFunding(
                        payment: payment,
                        onrampCoordinator: coordinator,
                        coinbaseService: coinbaseService,
                        router: router
                    )
                },
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
        .onChange(of: viewModel.fundingOperation?.state) { _, newState in
            // Single observer covers both push + reset:
            // - `nil` state → operation slot emptied → reset push tracking
            //   so a fresh op can push again on retry.
            // - First `.awaitingUserAction` transition for this op → push
            //   `.phantomFlow`. Preflight throws (NAME_EXISTS, DENIED) then
            //   surface on the buy screen itself instead of a stranded flow.
            // Assumes `PhantomFundingOperation` is single-shot per the
            // `FundingOperation` contract; identity-keyed tracking would
            // need to widen if instances ever get reused.
            guard let newState else {
                phantomFlowPushedFor = nil
                return
            }
            guard let operation = viewModel.fundingOperation as? PhantomFundingOperation,
                  case .awaitingUserAction = newState else { return }
            let id = ObjectIdentifier(operation)
            guard phantomFlowPushedFor != id else { return }
            phantomFlowPushedFor = id
            router.push(.phantomFlow(operation))
        }
    }

    private func showCurrencySelection() {
        isShowingCurrencySelection.toggle()
    }
}
