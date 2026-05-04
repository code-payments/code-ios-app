//
//  CurrencyCreationPromoCard.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

struct CurrencyCreationPromoCard: View {
    let onCreate: () -> Void

    var body: some View {
        Button(action: onCreate) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("Create Your Own Currency")
                            .font(.appTextLarge)
                            .foregroundStyle(Color.textMain)
                            .fixedSize(horizontal: false, vertical: true)
                        Image.system(.arrowRight)
                            .foregroundStyle(Color.textMain)
                    }
                    Text("Create a currency in minutes and immediately use it as cash")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(.CurrencyDiscovery.bills)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120)
            }
            .padding(16)
            .background(Color.backgroundSecondary)
            .compositingGroup()
            .clipShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("discover-create-currency-card")
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
}
