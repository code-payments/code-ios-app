//
//  WalletCurrenciesScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// Every currency the wallet holds, behind "N currencies" on the Money screen.
/// The balances today's wallet draws a card for, as rows; a row opens the
/// currency as tapping its card does.
struct WalletCurrenciesScreen: View {

    @Environment(Session.self) private var session
    @Environment(RatesController.self) private var ratesController
    @Environment(AppRouter.self) private var router

    private var balances: [ExchangedBalance] {
        Session.walletCardBalances(from: session.balances(for: ratesController.rateForBalanceCurrency()))
    }

    var body: some View {
        // Read once, so `isEmpty` and `ForEach` don't each re-sort the balances.
        let balances = self.balances

        Background(color: .backgroundMain) {
            if balances.isEmpty {
                Text("No currencies yet")
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 40)
                    .accessibilityIdentifier("wallet-currencies-empty")
            } else {
                List {
                    Section {
                        ForEach(balances) { balance in
                            CurrencyBalanceRow(
                                exchangedBalance: balance,
                                accessibilityIdentifier: "wallet-currency-row",
                                accessory: .chevron,
                                amountStyle: .pill
                            ) {
                                Analytics.tokenInfoOpened(from: .openedFromWallet, mint: balance.stored.mint)
                                router.push(.currencyInfo(balance.stored.mint))
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
        .navigationTitle("Currencies")
        .toolbarTitleDisplayMode(.inline)
    }
}
