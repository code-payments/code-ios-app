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

    @Environment(\.dismiss) private var dismiss
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
        self.viewModel        = WithdrawViewModel(
            container: container,
            sessionContainer: sessionContainer
        )
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
            case .enterAmount:
                WithdrawAmountScreen(viewModel: viewModel)
            case .enterAddress:
                WithdrawAddressScreen(viewModel: viewModel)
            case .confirmation:
                WithdrawSummaryScreen(viewModel: viewModel)
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
                // Settings root by popping `.withdraw` and any substeps
                // pushed on top.
                dismiss()
            }
        }
    }
}
