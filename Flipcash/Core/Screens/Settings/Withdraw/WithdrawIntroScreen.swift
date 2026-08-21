//
//  WithdrawIntroScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

struct WithdrawIntroScreen: View {

    let onNext: () -> Void

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 24) {
                Spacer()

                ConversionGraphic(from: .dollars, to: .usdcOnSolana)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Convert Dollars to USDC")

                VStack(spacing: 8) {
                    Text("Withdraw as USDC")
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)

                    Text("Your Dollars will be converted 1:1 to USDC on Solana")
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 40)

                Spacer()

                Button("Next", action: onNext)
                    .buttonStyle(.filled)
            }
            .padding(20)
        }
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
    }
}
