//
//  WithdrawScreen.swift
//  Flipcash
//
//  Created by Dima Bart on 2021-03-02.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// The withdraw flow's first screen: a currency picker listing every balance
/// that carries a displayable value, Dollars included — a balance rounding to
/// zero can't fund a withdrawal, so it's left out. Selecting Dollars detours
/// through the "Withdraw as USDC" intro; any other currency goes straight to
/// the amount screen.
struct WithdrawScreen: View {

    @Environment(Session.self) private var session
    @Environment(RatesController.self) private var ratesController

    let onSelect: (ExchangedBalance) -> Void

    private var balances: [ExchangedBalance] {
        session.balances(for: ratesController.rateForBalanceCurrency())
            .withdrawable()
    }

    var body: some View {
        // Cache the body-time computed property so `if balances.isEmpty` and
        // `ForEach(balances)` don't each re-run `session.balances(for:).filter`.
        let balances = self.balances

        Background(color: .backgroundMain) {
            if balances.isEmpty {
                Text("No currencies to withdraw")
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 40)
                    .accessibilityIdentifier("withdraw-picker-empty")
            } else {
                List {
                    Section {
                        ForEach(balances) { balance in
                            CurrencyBalanceRow(
                                exchangedBalance: balance,
                                accessory: .chevron,
                                amountStyle: .pill
                            ) {
                                onSelect(balance)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listSectionSeparator(.hidden, edges: .top)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .softScrollEdge(for: .top)
            }
        }
        .navigationTitle("Select Currency")
        .toolbarTitleDisplayMode(.inline)
    }
}

extension View {

    /// Registers the `WithdrawNavigationPath` substeps on the enclosing
    /// `NavigationStack`. Applied at the root of every withdraw flow
    /// (`WithdrawFlowRoot`), so every substep — picker, intro, amount,
    /// address, confirmation — resolves against the same view model.
    func withdrawSubstepDestinations(viewModel: WithdrawViewModel) -> some View {
        navigationDestination(for: WithdrawNavigationPath.self) { path in
            WithdrawSubstepDestination(path: path, viewModel: viewModel)
        }
    }
}

struct WithdrawSubstepDestination: View {

    let path: WithdrawNavigationPath
    @Bindable var viewModel: WithdrawViewModel

    var body: some View {
        switch path {
        case .picker:
            WithdrawScreen(onSelect: viewModel.selectCurrency)
                .dialog(item: $viewModel.dialogItem)
        case .intro:
            WithdrawIntroScreen(onNext: viewModel.continueFromIntro)
                .dialog(item: $viewModel.dialogItem)
        case .enterAmount:
            WithdrawAmountScreen(
                title: "Amount to Withdraw",
                enteredAmount: $viewModel.enteredAmount,
                subtitle: viewModel.amountSubtitle,
                canProceed: viewModel.canProceedToAddress,
                onProceed: viewModel.amountEnteredAction,
                showsCurrencySelection: true
            )
            .dialog(item: $viewModel.dialogItem)
        case .enterAddress:
            WithdrawAddressScreen(
                promptCurrencyName: viewModel.kind?.destinationCurrencyName ?? "funds",
                enteredAddress: $viewModel.enteredAddress,
                destinationMetadata: viewModel.destinationMetadata,
                acceptsTokenAccount: viewModel.kind?.acceptsTokenAccount ?? true,
                canCompleteWithdrawal: viewModel.canCompleteWithdrawal,
                onPasteFromClipboard: viewModel.pasteFromClipboardAction,
                onNext: viewModel.addressEnteredAction
            )
            .dialog(item: $viewModel.dialogItem)
        case .confirmation:
            WithdrawSummaryScreen(viewModel: viewModel)
                .dialog(item: $viewModel.dialogItem)
        }
    }
}
