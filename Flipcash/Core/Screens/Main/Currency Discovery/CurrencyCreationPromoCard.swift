//
//  CurrencyCreationPromoCard.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

struct CurrencyCreationPromoCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Create Your Own Currency")
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                    Image.system(.arrowRight)
                        .foregroundStyle(Color.textMain)
                }
                Text("Create a currency in minutes and\nimmediately use it as cash")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .bottomTrailing) {
                Image(.CurrencyDiscovery.bills)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120)
            }
            .background(Color.backgroundRow)
            .compositingGroup()
            .clipShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("discover-create-currency-card")
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
}
