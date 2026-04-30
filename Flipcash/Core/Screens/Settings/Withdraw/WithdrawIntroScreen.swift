//
//  WithdrawIntroScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

struct WithdrawIntroScreen: View {

    @Environment(AppRouter.self) private var router

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 24) {
                Spacer()

                ConversionGraphic()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Convert USDF to USDC")

                VStack(spacing: 8) {
                    Text("Withdraw as USDC")
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)

                    Text("Your USDF will be converted 1:1 to Solana USDC on withdrawal")
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 40)

                Spacer()

                Button("Next") {
                    router.pushAny(WithdrawNavigationPath.enterAmount)
                }
                .buttonStyle(.filled)
            }
            .padding(20)
        }
        .navigationTitle("Withdraw")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ConversionGraphic: View {
    var body: some View {
        HStack(spacing: 16) {
            Image.asset(.flipcash)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)

            Image.system(.arrowRight)
                .foregroundStyle(Color.textSecondary)

            // The solanaUSDC asset's viewBox is 143×145 because the Solana
            // hex badge sits down-right of the main USDC circle (which is
            // 128.3 wide within the viewBox). Frame ratio 111×113 scales the
            // viewBox so the main circle renders at ≈100×100, matching the
            // Flipcash icon. The offset pulls the asset down-right so the
            // main circle's center aligns with the Flipcash circle's center
            // (the asset's geometric center is offset by the badge weight).
            Image.asset(.solanaUSDC)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 111, height: 113)
                .offset(x: 6, y: 7)
        }
    }
}
