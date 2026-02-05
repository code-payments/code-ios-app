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
    @State private var isShowingDeposit: Bool = false

    private var balances: [ExchangedBalance] {
        session.balances(for: ratesController.rateForEntryCurrency())
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
        .navigationDestination(isPresented: $isShowingDeposit) {
            if let balance = selectedBalance {
                DepositScreen(
                    cluster: depositCluster(for: balance.stored),
                    name: balance.stored.name
                )
            }
        }
    }

    // MARK: - Actions -

    private func selectCurrency(_ balance: ExchangedBalance) {
        selectedBalance = balance
        isShowingDeposit = true
    }

    private func depositCluster(for balance: StoredBalance) -> AccountCluster {
        session.owner.use(
            mint: balance.mint,
            timeAuthority: balance.vmAuthority!
        )
    }
}
