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
    let balance: Quarks
    let appreciation: (amount: Quarks, isPositive: Bool)
    let isUSDF: Bool
    let onCurrencySelection: () -> Void
    let onViewTransaction: () -> Void

    var body: some View {
        VStack {
            Button {
                onCurrencySelection()
            } label: {
                AmountText(
                    flagStyle: balance.currencyCode.flagStyle,
                    content: balance.formatted(),
                    showChevron: true
                )
                .font(.appDisplayLarge)
                .foregroundStyle(Color.textMain)
            }
            .frame(height: 60)
            .frame(maxWidth: .infinity)

            if !isUSDF && balance.quarks > 0 {
                ValueAppreciation(amount: appreciation.amount, isPositive: appreciation.isPositive)
                    .padding(.top, 8)

                Button("View Transaction") {
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
