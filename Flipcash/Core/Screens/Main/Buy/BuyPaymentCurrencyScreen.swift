//
//  BuyPaymentCurrencyScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

struct BuyPaymentCurrencyScreen: View {

    @State private var viewModel: BuyPaymentCurrencyViewModel

    @Environment(AppRouter.self) private var router

    init(targetMint: PublicKey, targetName: String, entered: FiatAmount, session: Session, ratesController: RatesController) {
        self._viewModel = State(initialValue: BuyPaymentCurrencyViewModel(
            targetMint: targetMint,
            targetName: targetName,
            entered: entered,
            session: session,
            ratesController: ratesController
        ))
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        Background(color: .backgroundMain) {
            // Mirrors DepositCurrencyListScreen's construction — the two
            // pickers must stay visually interchangeable.
            List {
                Section {
                    ForEach(viewModel.rows) { row in
                        CurrencyBalanceRow(
                            exchangedBalance: row,
                            accessibilityIdentifier: row.stored.mint == .usdf ? "payment-currency-row-usdf" : "payment-currency-row",
                            accessory: .chevron,
                            amountStyle: .pill,
                            usesSymbol: row.stored.mint == .usdf
                        ) {
                            Task { await viewModel.select(row, router: router) }
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
                .listSectionSeparator(.hidden, edges: .top)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Select Payment Currency")
        .toolbarTitleDisplayMode(.inline)
        .dialog(item: $viewModel.dialogItem)
    }
}
