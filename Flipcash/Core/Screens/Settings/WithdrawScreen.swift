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

    @Binding var isPresented: Bool

    @EnvironmentObject private var session: Session
    @Environment(RatesController.self) private var ratesController

    @StateObject private var viewModel: WithdrawViewModel

    private let container: Container
    private let sessionContainer: SessionContainer

    private var balances: [ExchangedBalance] {
        session.balances(for: ratesController.rateForBalanceCurrency())
    }

    // MARK: - Init -

    init(isPresented: Binding<Bool>, container: Container, sessionContainer: SessionContainer) {
        self._isPresented     = isPresented
        self.container        = container
        self.sessionContainer = sessionContainer
        self._viewModel       = .init(
            wrappedValue: WithdrawViewModel(
                isPresented: isPresented,
                container: container,
                sessionContainer: sessionContainer
            )
        )
    }

    // MARK: - Body -

    var body: some View {
        NavigationStack(path: $viewModel.path) {
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
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarCloseButton(binding: $isPresented)
                }
            }
        }
    }
}
