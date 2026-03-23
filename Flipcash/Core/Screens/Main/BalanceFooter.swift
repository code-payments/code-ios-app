//
//  BalanceFooter.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

struct BalanceFooter: View {
    let reservesBalance: ExchangedBalance?
    let showDiscoverCurrencies: Bool
    @Binding var selectedMint: PublicKey?
    @Binding var isShowingCurrencyDiscovery: Bool

    var body: some View {
        VStack {
            if let reservesBalance, reservesBalance.exchangedFiat.hasDisplayableValue() {
                CashReservesRow(
                    reservesBalance: reservesBalance,
                    selectedMint: $selectedMint
                )
            }

            if showDiscoverCurrencies {
                Button("Discover Currencies") {
                    isShowingCurrencyDiscovery = true
                }
                .buttonStyle(.filled10)
                .padding(20)
            }
        }
    }
}

struct CashReservesRow: View {
    let reservesBalance: ExchangedBalance
    @Binding var selectedMint: PublicKey?

    var body: some View {
        VStack {
            Divider()

            Button {
                Analytics.tokenInfoOpened(from: .openedFromWallet, mint: reservesBalance.stored.mint)
                selectedMint = reservesBalance.stored.mint
            } label: {
                HStack(spacing: 8) {
                    Text("USDF")
                        .font(.appBarButton)
                        .foregroundStyle(Color.textSecondary)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                        .padding(.top, 3)

                    Spacer()

                    Text(reservesBalance.exchangedFiat.converted.formatted())
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                }
            }
            .listRowBackground(Color.clear)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .textCase(.none)

            Divider()
        }
    }
}
