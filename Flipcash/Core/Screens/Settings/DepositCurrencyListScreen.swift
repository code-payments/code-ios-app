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

    private var balances: [ExchangedBalance] {
        session.balances(for: ratesController.rateForEntryCurrency())
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
