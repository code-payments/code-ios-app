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
            List {
                Section {
                    ForEach(viewModel.rows) { row in
                        CurrencyBalanceRow(
                            exchangedBalance: row,
                            accessibilityIdentifier: row.stored.mint == .usdf ? "payment-currency-row-usdf" : "payment-currency-row",
                            accessory: .chevron,
                            action: {
                                Task { await viewModel.select(row, router: router) }
                            }
                        )
                        .vSeparator(color: .rowSeparator)
                    }
                }
                .listRowInsets(EdgeInsets())
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Select Payment Currency")
        .toolbarTitleDisplayMode(.inline)
        .dialog(item: $viewModel.dialogItem)
    }
}
