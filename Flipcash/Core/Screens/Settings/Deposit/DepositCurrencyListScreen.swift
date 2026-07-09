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

    /// When set, selecting a currency calls this instead of pushing
    /// `.depositAddress` on the router stack.
    private let onSelect: ((PublicKey) -> Void)?

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

    init(selectedMint: PublicKey? = nil, onSelect: ((PublicKey) -> Void)? = nil) {
        _selectedMint = State(initialValue: selectedMint)
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
        .onChange(of: balances, initial: true) {
            handleAutoSelect()
        }
    }

    // MARK: - Actions -

    private func selectCurrency(_ balance: ExchangedBalance) {
        navigate(to: balance.stored.mint)
    }

    private func handleAutoSelect() {
        guard let mint = selectedMint,
              balances.contains(where: { $0.stored.mint == mint }) else { return }
        selectedMint = nil
        navigate(to: mint)
    }

    private func navigate(to mint: PublicKey) {
        if let onSelect {
            onSelect(mint)
        } else {
            router.push(.depositAddress(mint))
        }
    }
}
