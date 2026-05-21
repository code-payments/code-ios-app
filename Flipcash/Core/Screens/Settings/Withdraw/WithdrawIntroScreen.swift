//
//  WithdrawIntroScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

struct WithdrawIntroScreen: View {

    let onNext: () -> Void
    let onWithdrawOtherCurrencies: (() -> Void)?

    init(onNext: @escaping () -> Void, onWithdrawOtherCurrencies: (() -> Void)? = nil) {
        self.onNext = onNext
        self.onWithdrawOtherCurrencies = onWithdrawOtherCurrencies
    }

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

                VStack(spacing: 8) {
                    Button("Next", action: onNext)
                        .buttonStyle(.filled)

                    if let onWithdrawOtherCurrencies {
                        Button("Withdraw Other Flipcash Currencies", action: onWithdrawOtherCurrencies)
                            .buttonStyle(.subtle)
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Withdraw")
        .toolbarTitleDisplayMode(.inline)
    }
}

private struct ConversionGraphic: View {
    var body: some View {
        HStack(spacing: 16) {
            Image.asset(.buyFlipcash)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)

            Image.system(.arrowRight)
                .foregroundStyle(Color.textSecondary)

            BadgedIcon(
                icon: Image.asset(.buyUSDC),
                badge: Image.asset(.buySolana)
            )
        }
    }
}
