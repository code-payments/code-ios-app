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
struct GiveScreen: View {

    @Environment(Session.self) private var session
    @Environment(RatesController.self) private var ratesController
    @Environment(AppRouter.self) private var router

    @State private var viewModel: GiveViewModel

    @State private var isShowingCurrencySelection: Bool = false
    @State private var isShowingTokenSelection: Bool = false

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
                currencySelectionAction: showCurrencySelection
            )
            .foregroundStyle(.textMain)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .padding(.top, -40)
            .sheet(isPresented: $isShowingCurrencySelection) {
                CurrencySelectionScreen(ratesController: ratesController)
            }
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
        .onChange(of: viewModel.depositMint) { _, mint in
            guard let mint else { return }
            // Clear the trigger so a subsequent tap re-fires the push.
            viewModel.depositMint = nil
            router.push(.currencyInfoForDeposit(mint))
        }
        .sheet(isPresented: $isShowingTokenSelection) {
            SelectCurrencyScreen(
                isPresented: $isShowingTokenSelection,
                kind: .give { balance in
                    viewModel.selectCurrencyAction(exchangedBalance: balance)
                },
                fixedRate: nil,
            )
        }
    }

    // MARK: - Actions -

    private func nextAction() {
        viewModel.giveAction()
    }

    private func showCurrencySelection() {
        isShowingCurrencySelection.toggle()
    }
}

// MARK: - TokenSelectorButton -

private struct TokenSelectorButton: View {
    let selectedBalance: ExchangedBalance?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                CurrencyLabel(
                    imageURL: selectedBalance?.stored.imageURL,
                    name: selectedBalance?.stored.name ?? "",
                    amount: nil
                )

                Image.system(.chevronDown)
                    .font(.default(size: 12, weight: .bold))
                    .foregroundStyle(.textMain)
            }
        }
    }
}
