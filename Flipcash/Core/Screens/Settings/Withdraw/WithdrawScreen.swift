//
//  WithdrawScreen.swift
//  Flipcash
//
//  Created by Dima Bart on 2021-03-02.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct WithdrawScreen: View {

    @Environment(AppRouter.self) private var router
    @Environment(Session.self) private var session
    @Environment(RatesController.self) private var ratesController

    @State private var viewModel: WithdrawViewModel

    private let container: Container
    private let sessionContainer: SessionContainer

    private var balances: [ExchangedBalance] {
        session.balances(for: ratesController.rateForBalanceCurrency())
    }

    // MARK: - Init -

    init(container: Container, sessionContainer: SessionContainer) {
        self.container        = container
        self.sessionContainer = sessionContainer
        self._viewModel       = State(wrappedValue: WithdrawViewModel(
            container: container,
            sessionContainer: sessionContainer
        ))
    }

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            List {
                Section {
                    ForEach(balances) { balance in
                        CurrencyBalanceRow(
                            exchangedBalance: balance
                        ) {
                            viewModel.selectCurrency(balance)
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Select Currency")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: WithdrawNavigationPath.self) { path in
            switch path {
            case .intro:
                WithdrawIntroScreen()
                    .dialog(item: $viewModel.dialogItem)
            case .enterAmount:
                WithdrawAmountScreen(
                    title: viewModel.withdrawTitle,
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
        .onAppear {
            // Wire the view model's navigation callbacks. Push substeps onto
            // the parent (Settings) NavigationStack via the router; pops
            // remove that many items from the top.
            viewModel.pushSubstep = { step in
                router.pushAny(step)
            }
            viewModel.popSubsteps = { count in
                router.popLast(count, on: .settings)
            }
            viewModel.onComplete = {
                // Successful withdrawal: unwind the entire flow back to
                // Settings root. Using `dismiss()` here would tear down the
                // whole Settings sheet and land the user back at Scan.
                router.popToRoot(on: .settings)
            }
        }
    }
}
