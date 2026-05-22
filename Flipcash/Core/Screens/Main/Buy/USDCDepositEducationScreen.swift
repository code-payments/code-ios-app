//
//  USDCDepositEducationScreen.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-05-12.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// Pre-flight for the USDC → USDF conversion: explains that incoming Solana
/// USDC is auto-converted 1:1 to USDF on receipt. Pass `onDepositOtherCurrencies`
/// to expose a subtle escape hatch below Next.
struct USDCDepositEducationScreen: View {

    let onNext: () -> Void
    let onDepositOtherCurrencies: (() -> Void)?

    init(onNext: @escaping () -> Void, onDepositOtherCurrencies: (() -> Void)? = nil) {
        self.onNext = onNext
        self.onDepositOtherCurrencies = onDepositOtherCurrencies
    }

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
        .navigationTitle("Deposit")
        .toolbarTitleDisplayMode(.inline)
    }
}

private struct ConversionGraphic: View {
    var body: some View {
        HStack(spacing: 16) {
            BadgedIcon(
                icon: Image.asset(.buyUSDC),
                badge: Image.asset(.buySolana)
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
