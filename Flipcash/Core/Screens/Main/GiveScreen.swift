//
//  GiveScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-04-17.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// Amount entry screen for giving cash to another user. Caller provides the
/// surrounding `NavigationStack` (sheet wraps it, push uses the active one).
///
/// Thin environment-reading wrapper that hands the DI containers to
/// ``GiveScreenContent``, whose `init` seeds the `@State` view model
/// synchronously. `.id(mint)` on this wrapper at the call site rebuilds the
/// content (and its view model) when the mint changes.
struct GiveScreen: View {

    @Environment(Container.self) private var container
    @Environment(SessionContainer.self) private var sessionContainer

    let mint: PublicKey?

    var body: some View {
        GiveScreenContent(
            container: container,
            sessionContainer: sessionContainer,
            mint: mint
        )
    }
}

private struct GiveScreenContent: View {

    @Environment(Session.self) private var session
    @Environment(RatesController.self) private var ratesController
    @Environment(AppRouter.self) private var router

    @State private var viewModel: GiveViewModel

    @State private var isShowingTokenSelection: Bool = false

    /// True when this screen was pushed (from a currency's Give tile) rather
    /// than hosted at a tab root (the Scan tab). Only the pushed instance pops
    /// itself when the bill appears.
    private let isPushed: Bool

    private var maxLimit: ExchangedFiat {
        let rate = ratesController.rateForBalanceCurrency()
        let zero = ExchangedFiat.compute(
            onChainAmount: .zero(mint: .usdf),
            rate: rate,
            supplyQuarks: nil
        )

        guard let mint = viewModel.selectedBalance?.stored.mint else {
            return zero
        }

        guard let balance = session.balance(for: mint) else {
            return zero
        }

        return balance.computeExchangedValue(with: rate)
    }

    // MARK: - Init -

    init(container: Container, sessionContainer: SessionContainer, mint: PublicKey?) {
        _viewModel = State(initialValue: GiveViewModel(
            container: container,
            sessionContainer: sessionContainer,
            mint: mint
        ))
        // The Scan tab hosts Give at its root with no mint; a currency's Give
        // tile pushes it with the currency mint.
        self.isPushed = mint != nil
    }

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            EnterAmountView(
                mode: .currency,
                enteredAmount: $viewModel.enteredAmount,
                subtitle: .balanceWithLimit(maxLimit),
                actionState: $viewModel.actionState,
                actionEnabled: { _ in
                    viewModel.canGive
                },
                action: nextAction,
                header: AnyView(EnterAmountHeader(
                    enteredAmount: $viewModel.enteredAmount,
                    hint: .available(maxLimit)
                ))
            )
            .foregroundStyle(.textMain)
            .padding(20)
        }
        .ignoresSafeArea(.keyboard)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                TokenSelectorButton(
                    selectedBalance: viewModel.selectedBalance,
                    action: { isShowingTokenSelection = true }
                )
                .id(viewModel.selectedBalance?.stored.mint)
            }
        }
        .onAppear {
            // When pushed from a currency's Give tile, pop this entry screen as
            // the bill appears so the bill sits over the currency info. The pop
            // is un-animated so the entry doesn't visibly slide back out from
            // under the bill. The Scan tab's root instance leaves it nil.
            viewModel.onBillPresented = isPushed ? {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { router.popTopmost() }
            } : nil
        }
        .onChange(of: viewModel.depositMint) { _, mint in
            guard let mint else { return }
            // Clear the trigger so a subsequent tap re-fires the push.
            viewModel.depositMint = nil
            router.push(.currencyInfoForDeposit(mint))
        }
        .sheet(isPresented: $isShowingTokenSelection) {
            SelectCurrencyScreen(isPresented: $isShowingTokenSelection) { balance in
                viewModel.selectCurrencyAction(exchangedBalance: balance)
            }
        }
    }

    // MARK: - Actions -

    private func nextAction() {
        viewModel.giveAction()
    }
}

