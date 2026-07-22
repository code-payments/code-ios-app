//
//  TokenSelectorButton.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore

/// The selected-currency affordance shared by the amount-entry surfaces: the
/// currency's image and name with a disclosure chevron, opening the
/// held-currency picker.
struct TokenSelectorButton: View {

    let selectedBalance: ExchangedBalance?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                CurrencyLabel(
                    imageURL: selectedBalance?.stored.imageURL,
                    name: selectedBalance?.stored.name ?? "",
                    amount: nil
                )

                Image.system(.chevronDown)
                    .font(.default(size: 12, weight: .bold))
                    .foregroundStyle(.textMain)
            }
        }
    }
}
