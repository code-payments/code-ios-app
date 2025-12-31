//
//  CurrencySellConfirmationScreen.swift
//  Code
//
//  Created by Raul Riera on 2025-12-30.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct CurrencySellConfirmationScreen: View {
    let mint: PublicKey
    let amount: ExchangedFiat
    var fee: ExchangedFiat {
        let bps: UInt64 = 100
        let underlaying = Quarks(quarks: amount.underlying.quarks * bps / 10_000, currencyCode: amount.underlying.currencyCode, decimals: amount.underlying.decimals)
        let converted = Quarks(quarks: amount.converted.quarks * bps / 10_000, currencyCode: amount.converted.currencyCode, decimals: amount.converted.decimals)
        
        return ExchangedFiat(underlying: underlaying,
                             converted: converted,
                             rate: amount.rate, mint: amount.mint)
    }
    var amountAfterFee: ExchangedFiat {
        do {
            return try amount.subtracting(fee)
        } catch {
            // FIXME: How do we handle subtracting failures?
            return amount
        }
    }
    
    @State private var dialogItem: DialogItem?
    @State private var actionButtonState: ButtonState = .normal
    @EnvironmentObject private var session: Session
    @Environment(\.dismissParentContainer) private var dismissParentContainer
        
    var body: some View {
        Background(color: .backgroundMain) {
            VStack {
                Spacer()
                
                BorderedContainer {
                    VStack(spacing: 10) {
                        HStack {
                            Text("Sell amount")
                            Spacer()
                            Text(amount.converted.formatted())
                                .font(.appTextMedium)
                                .foregroundStyle(Color.textMain)
                        }
                        
                        HStack {
                            Text("1% Free")
                            Spacer()
                            Text(fee.converted.formatted())
                                .font(.appTextMedium)
                                .foregroundStyle(Color.textMain)
                        }
                    }
                    .padding()
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)

                    VStack {
                        Text("You Receive")
                            .font(.appTextSmall)
                            .foregroundStyle(Color.textSecondary)
                        AmountText(
                            flagStyle: amountAfterFee.converted.currencyCode.flagStyle,
                            content: amountAfterFee.converted.formatted(),
                            showChevron: false,
                            canScale: false
                        )
                        .font(.appDisplaySmall)
                        .foregroundStyle(Color.textMain)
                    }
                    .padding(.bottom, 32)
                }
                
                Spacer()
                
                VStack {
                    Text("Review the above before confirming.\nOnce made, your transaction is irreverible.")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                    CodeButton(state: actionButtonState,
                        style: .filled,
                        title: "Sell",
                        action: performSell
                    )
                        .padding(.top, 20)
                }
            }
            .padding(20)
        }
        .dialog(item: $dialogItem)
        .navigationTitle("Confirm Sale")
    }
    
    // MARK: - Actions -
    
    private func performSell() {
        actionButtonState = .loading

        Task {
            do {
                try await session.sell(amount: amount, in: mint)

                await MainActor.run {
                    showSuccessDialog()
                }
            } catch (let error) {
                await MainActor.run {
                    actionButtonState = .normal
                    showErrorDialog(error: error)
                }
            }
        }
    }
    
    // MARK: - Dialogs -
    
    private func showSuccessDialog() {
        dialogItem = .init(
            style: .success,
            title: "Your Funds Will Be Available Soon",
            subtitle: "They should be available in a few minutes. If you have any issues please contact support@flipcash.com",
            dismissable: false
        ) {
            .okay(kind: .standard) {
                actionButtonState = .success
                dismissParentContainer()
            }
        }
    }
    
    private func showErrorDialog(error: Error) {
        dialogItem = .init(
            style: .destructive,
            title: "Insufficient Balance",
            subtitle: "Please enter a lower amount and try again, \(error)",
            dismissable: true
        ) {
            .okay(kind: .destructive) {
                actionButtonState = .normal
            }
        }
    }
}

#Preview {
    let amount = try! ExchangedFiat(underlying: 10_000_000_000_000, rate: .oneToOne, mint: .usdc)
    CurrencySellConfirmationScreen(mint: .usdc, amount: amount)
}
