//
//  CurrencyInfoHeaderSection.swift
//  Code
//
//  Created by Raul Riera on 2026-03-24.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct CurrencyInfoHeaderSection: View {
    let balance: FiatAmount
    let appreciation: (amount: FiatAmount, isPositive: Bool)
    let isUSDF: Bool
    let onCurrencySelection: () -> Void
    let onViewTransaction: () -> Void

    var body: some View {
        VStack {
            Button {
                onCurrencySelection()
            } label: {
                AmountText(
                    flagStyle: balance.currency.flagStyle,
                    content: balance.formatted(),
                    showChevron: true
                )
                .font(.appDisplayLarge)
                .foregroundStyle(Color.textMain)
                .contentTransition(.numericText())
            }
            .frame(height: 60)
            .frame(maxWidth: .infinity)
            .animation(.default, value: balance)

            if !isUSDF && balance.isPositive {
                ValueAppreciation(amount: appreciation.amount, isPositive: appreciation.isPositive)
                    .padding(.top, 8)

                Button("Transaction History") {
                    onViewTransaction()
                }
                    .buttonStyle(.filled20)
                    .padding(.top, 40)
            }
        }
        .padding(.top, 30)
        .padding(.bottom, 25)
        .vSeparator(color: .rowSeparator)
        .padding(.horizontal, 20)
    }
}
