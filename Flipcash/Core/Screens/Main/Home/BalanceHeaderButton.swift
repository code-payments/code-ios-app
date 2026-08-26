//
//  BalanceHeaderButton.swift
//  Code
//
//  Created by Dima Bart on 2025-04-23.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// The wallet's total-balance display; tapping it opens the balance-currency
/// picker.
struct BalanceHeaderButton: View {
    let balance: ExchangedFiat

    @Environment(RatesController.self) private var ratesController
    @State private var isShowingCurrencySelection = false

    var body: some View {
        VStack(spacing: 10) {
            Button {
                isShowingCurrencySelection.toggle()
            } label: {
                AmountText(
                    flagStyle: balance.nativeAmount.currency.flagStyle,
                    content: balance.nativeAmount.formatted(),
                    showChevron: true
                )
                .font(.appDisplayLarge)
                .foregroundStyle(Color.textMain)
                .contentTransition(.numericText())
            }
            .accessibilityIdentifier("balance-header")
            .frame(maxWidth: .infinity)
            .animation(.default, value: balance)
            .sheet(isPresented: $isShowingCurrencySelection) {
                CurrencySelectionScreen(ratesController: ratesController)
            }
        }
    }
}
