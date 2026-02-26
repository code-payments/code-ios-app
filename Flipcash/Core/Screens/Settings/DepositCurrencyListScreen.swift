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

    @EnvironmentObject private var session: Session
    @EnvironmentObject private var ratesController: RatesController

    @State private var selectedBalance: ExchangedBalance?
    @State private var selectedMint: PublicKey?

    // Skip session.balances(for:) to avoid filtering out zero-balance currencies.
    // For deposits, we want to show every currency the user has an account for.
    private var balances: [ExchangedBalance] {
        let rate = ratesController.rateForEntryCurrency()
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
        .navigationDestination(item: $selectedBalance) { balance in
            DepositScreen(
                cluster: depositCluster(for: balance.stored),
                name: balance.stored.name
            )
        }
        .onAppear {
            handleAutoSelect()
        }
    }

    // MARK: - Actions -

    private func selectCurrency(_ balance: ExchangedBalance) {
        selectedBalance = balance
    }

    private func handleAutoSelect() {
        guard let mint = selectedMint else { return }
        selectedMint = nil
        selectedBalance = balances.first(where: { $0.stored.mint == mint })
    }

    private func depositCluster(for balance: StoredBalance) -> AccountCluster {
        session.owner.use(
            mint: balance.mint,
            timeAuthority: balance.vmAuthority!
        )
    }
}
