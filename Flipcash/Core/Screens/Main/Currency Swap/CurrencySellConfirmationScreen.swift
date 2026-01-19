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
    
    @StateObject private var viewModel: CurrencySellConfirmationViewModel
    
    @EnvironmentObject private var session: Session
    @Environment(\.dismissParentContainer) private var dismissParentContainer
    
    // MARK: - Init -
    
    init(mint: PublicKey, amount: ExchangedFiat) {
        self.mint = mint
        self.amount = amount
        self._viewModel = StateObject(wrappedValue: CurrencySellConfirmationViewModel(mint: mint, amount: amount))
    }
        
    var body: some View {
        Background(color: .backgroundMain) {
            VStack {
                Spacer()
                
                BorderedContainer {
                    VStack(spacing: 10) {
                        HStack {
                            Text("Sell amount")
                            Spacer()
                            Text(viewModel.amount.converted.formatted())
                                .font(.appTextMedium)
                                .foregroundStyle(Color.textMain)
                        }
                        
                        HStack {
                            Text("1% Fee")
                            Spacer()
                            Text(viewModel.fee.converted.formatted())
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
                            flagStyle: viewModel.amountAfterFee.converted.currencyCode.flagStyle,
                            content: viewModel.amountAfterFee.converted.formatted(),
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
                    CodeButton(state: viewModel.actionButtonState,
                        style: .filled,
                        title: "Sell",
                        action: performSell
                    )
                        .padding(.top, 20)
                }
            }
            .padding(20)
        }
        .interactiveDismissDisabled(!viewModel.canDismissSheet)
        .dialog(item: $viewModel.dialogItem)
        .navigationTitle("Confirm Sale")
    }
    
    // MARK: - Actions -
    
    private func performSell() {
        viewModel.performSell(using: session, onDismiss: dismissParentContainer)
    }
}

#Preview {
    let amount = try! ExchangedFiat(underlying: 10_000_000_000_000, rate: .oneToOne, mint: .usdc)
    CurrencySellConfirmationScreen(mint: .usdc, amount: amount)
}
