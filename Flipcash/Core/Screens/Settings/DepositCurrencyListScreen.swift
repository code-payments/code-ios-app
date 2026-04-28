//
//  DepositCurrencyListScreen.swift
//  Code
//
//  Created by Raul Riera on 2026-02-05.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct DepositCurrencyListScreen: View {

    @Environment(Session.self) private var session
    @Environment(RatesController.self) private var ratesController
    @Environment(AppRouter.self) private var router

    @State private var selectedMint: PublicKey?

    // Skip session.balances(for:) to avoid filtering out zero-balance currencies.
    // For deposits, we want to show every currency the user has an account for.
    private var balances: [ExchangedBalance] {
        let rate = ratesController.rateForBalanceCurrency()
        return session.balances.map { stored in
            ExchangedBalance(
                stored: stored,
                exchangedFiat: stored.computeExchangedValue(with: rate)
            )
        }
    }

    init(selectedMint: PublicKey? = nil) {
        _selectedMint = State(initialValue: selectedMint)
    }

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            List {
                Section {
                    ForEach(balances) { balance in
                        CurrencyBalanceRow(exchangedBalance: balance) {
                            selectCurrency(balance)
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
        .onAppear {
            handleAutoSelect()
        }
    }

    // MARK: - Actions -

    private func selectCurrency(_ balance: ExchangedBalance) {
        router.push(.deposit(balance.stored.mint), on: .settings)
    }

    private func handleAutoSelect() {
        guard let mint = selectedMint,
              balances.contains(where: { $0.stored.mint == mint }) else { return }
        selectedMint = nil
        router.push(.deposit(mint), on: .settings)
    }
}
