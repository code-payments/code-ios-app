//
//  USDCDepositEducationScreen.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-05-12.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// Pre-flight for the USDC → Dollars conversion: explains that incoming Solana
/// USDC is auto-converted 1:1 to Dollars on receipt. Pass `onDepositOtherCurrencies`
/// to expose a subtle escape hatch below Next.
struct USDCDepositEducationScreen: View {

    let title: String
    let onNext: () -> Void
    let onDepositOtherCurrencies: (() -> Void)?

    init(
        title: String = "Deposit",
        onNext: @escaping () -> Void,
        onDepositOtherCurrencies: (() -> Void)? = nil
    ) {
        self.title = title
        self.onNext = onNext
        self.onDepositOtherCurrencies = onDepositOtherCurrencies
    }

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 24) {
                Spacer()

                ConversionGraphic(from: .usdcOnSolana, to: .dollars)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Convert USDC to Dollars")

                VStack(spacing: 8) {
                    Text("Deposit USDC")
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)

                    Text("Your USDC will be converted 1:1 to Dollars on Flipcash")
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

                    if let onDepositOtherCurrencies {
                        Button("Deposit Other Flipcash Currencies", action: onDepositOtherCurrencies)
                            .buttonStyle(.subtle)
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle(title)
        .toolbarTitleDisplayMode(.inline)
    }
}
