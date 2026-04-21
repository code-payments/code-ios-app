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
    let currencyName: String
    let amount: ExchangedFiat
    @Binding var path: [CurrencySellPath]

    @State private var viewModel: CurrencySellConfirmationViewModel

    @Environment(Session.self) private var session

    // MARK: - Init -

    init(mint: PublicKey, currencyName: String, amount: ExchangedFiat, path: Binding<[CurrencySellPath]>) {
        self.currencyName = currencyName
        self.amount = amount
        self._path = path
        self.viewModel = CurrencySellConfirmationViewModel(mint: mint, amount: amount)
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
                            Text(viewModel.amount.nativeAmount.formatted())
                                .font(.appTextMedium)
                                .foregroundStyle(Color.textMain)
                        }
                        
                        HStack {
                            Text("1% Fee")
                            Spacer()
                            Text(viewModel.feeFormatted)
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
                            flagStyle: viewModel.amountAfterFee.nativeAmount.currency.flagStyle,
                            content: viewModel.amountAfterFee.nativeAmount.formatted(),
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
                    Text("Review the above before confirming.\nOnce made, your transaction is irreversible.")
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
        .onChange(of: viewModel.pendingSwapId) { _, swapId in
            if let swapId {
                path.append(.processing(swapId: swapId, currencyName: currencyName, amount: viewModel.amountAfterFee))
            }
        }
    }

    // MARK: - Actions -

    private func performSell() {
        viewModel.performSell(using: session)
    }
}

#Preview {
    @Previewable @State var path: [CurrencySellPath] = []
    let amount = ExchangedFiat.compute(
        onChainAmount: TokenAmount(quarks: 10_000_000_000_000, mint: .usdf),
        rate: .oneToOne,
        supplyQuarks: nil
    )
    CurrencySellConfirmationScreen(mint: .usdf, currencyName: "USDF", amount: amount, path: $path)
}
