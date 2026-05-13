//
//  USDCDepositEducationScreen.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-05-12.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// Pre-flight for the "Other Wallet" path: explains that incoming Solana USDC
/// is auto-converted 1:1 to USDF on receipt. Tapping Next pushes
/// `BuyFlowPath.usdcDepositAddress` so the user can copy the destination
/// address.
struct USDCDepositEducationScreen: View {

    let mint: PublicKey
    let amount: ExchangedFiat

    @Environment(AppRouter.self) private var router

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 24) {
                Spacer()

                ConversionGraphic()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Convert USDC to USDF")

                VStack(spacing: 8) {
                    Text("Deposit USDC")
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)

                    Text("Your Solana USDC will be converted 1:1 to USD on Flipcash (USDF)")
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 40)

                Spacer()

                Button("Next") {
                    router.pushAny(BuyFlowPath.usdcDepositAddress(mint: mint, amount: amount))
                }
                .buttonStyle(.filled)
            }
            .padding(20)
        }
        .navigationTitle("Deposit")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ConversionGraphic: View {
    var body: some View {
        HStack(spacing: 16) {
            BadgedIcon(
                icon: Image.asset(.buyUSDC),
                badge: Image.asset(.buySolana),
                size: 100,
                badgeSize: 32
            )

            Image.system(.arrowRight)
                .foregroundStyle(Color.textSecondary)

            Image.asset(.buyFlipcash)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
        }
    }
}
