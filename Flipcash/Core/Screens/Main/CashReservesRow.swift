//
//  CashReservesRow.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

struct CashReservesRow: View {
    let reservesBalance: ExchangedBalance
    let showTopDivider: Bool
    @Binding var selectedMint: PublicKey?

    var body: some View {
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
        .padding(20)
        .vSeparator(color: .rowSeparator, position: showTopDivider ? [.top, .bottom] : .bottom)
    }
}
