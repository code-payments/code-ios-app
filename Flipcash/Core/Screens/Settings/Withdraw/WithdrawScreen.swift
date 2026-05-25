//
//  WithdrawScreen.swift
//  Flipcash
//
//  Created by Dima Bart on 2021-03-02.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// Currency picker reached via the "Withdraw Other Flipcash Currencies" button
/// on `WithdrawIntroScreen`. Lists every balance except USDF — USDF lives on
/// the intro screen as the default destination, so it's removed from the
/// picker to avoid two paths to the same flow.
struct WithdrawScreen: View {

    @Environment(Session.self) private var session
    @Environment(RatesController.self) private var ratesController

    let onSelect: (ExchangedBalance) -> Void

    private var balances: [ExchangedBalance] {
        session.balances(for: ratesController.rateForBalanceCurrency())
            .filter { $0.stored.mint != .usdf }
    }

    var body: some View {
        // Cache the body-time computed property so `if balances.isEmpty` and
        // `ForEach(balances)` don't each re-run `session.balances(for:).filter`.
        let balances = self.balances

        Background(color: .backgroundMain) {
            if balances.isEmpty {
                Text("No other currencies to withdraw")
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
            }
        }
        .navigationTitle("Select Currency")
        .toolbarTitleDisplayMode(.inline)
    }
}

extension View {

    /// Registers the `WithdrawNavigationPath` substeps on the enclosing
    /// `NavigationStack`. Applied at the root of every withdraw flow
    /// (`PreselectedWithdrawRoot`), so every substep — picker, amount,
    /// address, confirmation — resolves against the same view model.
    func withdrawSubstepDestinations(viewModel: WithdrawViewModel) -> some View {
        navigationDestination(for: WithdrawNavigationPath.self) { path in
            WithdrawSubstepDestination(path: path, viewModel: viewModel)
        }
    }
}

private struct WithdrawSubstepDestination: View {

    let path: WithdrawNavigationPath
    @Bindable var viewModel: WithdrawViewModel

    var body: some View {
        switch path {
        case .picker:
            WithdrawScreen(onSelect: viewModel.selectCurrency)
                .dialog(item: $viewModel.dialogItem)
        case .enterAmount:
            WithdrawAmountScreen(
                title: "Withdraw",
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
