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

    private let onSelect: (PublicKey) -> Void

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

    init(onSelect: @escaping (PublicKey) -> Void) {
        self.onSelect = onSelect
    }

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            List {
                Section {
                    ForEach(balances) { balance in
                        CurrencyBalanceRow(
                            exchangedBalance: balance,
                            accessory: .chevron,
                            amountStyle: .pill,
                            usesSymbol: balance.stored.mint == .usdf
                        ) {
                            selectCurrency(balance)
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
                .listSectionSeparator(.hidden, edges: .top)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Select Currency")
        .toolbarTitleDisplayMode(.inline)
    }

    // MARK: - Actions -

    private func selectCurrency(_ balance: ExchangedBalance) {
        onSelect(balance.stored.mint)
    }
}
