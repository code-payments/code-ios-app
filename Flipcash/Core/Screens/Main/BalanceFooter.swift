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
    let isOnlyRow: Bool
    @Binding var selectedMint: PublicKey?
    @Binding var isShowingCurrencyDiscovery: Bool

    var body: some View {
        VStack {
            if let reservesBalance, reservesBalance.exchangedFiat.hasDisplayableValue() {
                CashReservesRow(
                    reservesBalance: reservesBalance,
                    showTopDivider: isOnlyRow,
                    selectedMint: $selectedMint
                )
            }

            if showDiscoverCurrencies {
                Button("Discover Currencies") {
                    isShowingCurrencyDiscovery = true
                }
                .buttonStyle(.filled)
                .padding(20)
            }
        }
    }
}

private struct CashReservesRow: View {
    let reservesBalance: ExchangedBalance
    let showTopDivider: Bool
    @Binding var selectedMint: PublicKey?

    var body: some View {
        VStack(spacing: 0) {
            if showTopDivider {
                Divider()
                    .overlay(Color.rowSeparator)
            }

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

                    Text(reservesBalance.exchangedFiat.nativeAmount.formatted())
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                        .contentTransition(.numericText())
                        .animation(.default, value: reservesBalance.exchangedFiat.nativeAmount)
                }
            }
            .listRowBackground(Color.clear)
            .padding(20)
            .textCase(.none)

            Divider()
                .overlay(Color.rowSeparator)
        }
    }
}
