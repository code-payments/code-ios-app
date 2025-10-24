//
//  WithdrawSummaryScreen.swift
//  Code
//
//  Created by Dima Bart on 2022-08-05.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct WithdrawSummaryScreen: View {
    
    @EnvironmentObject private var bannerController: BannerController
    
    @ObservedObject private var viewModel: WithdrawViewModel
    
    @State private var dialogItem: DialogItem?
    
    private var usdcToWithdraw: String {
        if let withdrawableAmount = viewModel.withdrawableAmount {
            return withdrawableAmount.usdc.formatted(suffix: nil)
            
        } else if let negativeDelta = viewModel.negativeWithdrawableAmount {
            return "-\(negativeDelta.formatted(suffix: nil))"
            
        } else {
            return Fiat(quarks: 0 as UInt64, currencyCode: .usd, decimals: PublicKey.usdc.mintDecimals).formatted(suffix: nil)
        }
    }
    
    // MARK: - Init -
    
    init(viewModel: WithdrawViewModel) {
        self.viewModel = viewModel
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            GeometryReader { geometry in
                VStack(alignment: .center, spacing: 20) {
                    Spacer()
                    
                    if
                        let enteredAmount = viewModel.enteredFiat,
                        let metadata = viewModel.destinationMetadata
                    {
                        let originalFiat = enteredAmount.converted
                        let usdcFiat     = enteredAmount.usdc
                        let fee          = metadata.fee
                        
                        BorderedContainer {
                            VStack(spacing: 20) {
                                
                                Spacer()
                                
                                AmountText(
                                    flagStyle: CurrencyCode.usd.flagStyle,
                                    content: usdcToWithdraw,
                                    showChevron: false,
                                    canScale: false
                                )
                                .font(.appDisplayMedium)
                                .foregroundStyle(Color.textMain)
                                
                                Spacer()
                                
                                if originalFiat.currencyCode != .usd || fee.quarks > 0 {
                                    VStack(alignment: .leading, spacing: 10) {
                                        lineItem(
                                            title: Text("Withdrawal amount"),
                                            value: originalFiat.formatted(suffix: nil)
                                        )
                                        
                                        if originalFiat.currencyCode != .usd {
                                            lineItem(
                                                title: Text("Converted to USD"),
                                                value: usdcFiat.formatted(/*truncated: true,*/suffix: nil)
                                            )
                                        }
                                        
                                        if fee.quarks > 0 {
                                            lineItem(
                                                title: Text("Less one time fee").underline() + Text(" \(Image.asset(.info))").baselineOffset(-2),
                                                value: "-\(fee.formatted(suffix: nil))"
                                            ) {
                                                showFeeInformationDialog()
                                            }
                                        }
                                    }
                                    
                                    Spacer()
                                }
                            }
                            .padding(20)
                            .frame(height: geometry.size.height * 0.35)
                        }
                    }
                    
                    Image.system(.arrowDown)
                        .foregroundColor(.textSecondary)
                    
                    BorderedContainer {
                        Text(viewModel.enteredDestination?.base58 ?? "<address>")
                            .font(.appDisplayXS)
                            .multilineTextAlignment(.center)
                            .padding(20)
                    }
                    
                    Spacer()
                    
                    CodeButton(
                        state: viewModel.withdrawButtonState,
                        style: .filled,
                        title: "Withdraw",
                        action: viewModel.completeWithdrawalAction
                    )
                }
                .padding(20)
            }
        }
        .navigationTitle("Withdraw")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled()
        .dialog(item: $dialogItem)
    }
    
    @ViewBuilder private func lineItem(title: Text, value: String, action: (() -> Void)? = nil) -> some View {
        HStack {
            if let action {
                Button {
                    action()
                } label: {
                    title
                        .foregroundStyle(Color.textSecondary)
                }
            } else {
                title
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Text(value)
                .foregroundStyle(Color.textMain)
        }
        .font(.appTextSmall)
    }
    
    // MARK: - Dialogs -
    
    private func showFeeInformationDialog() {
        dialogItem = .init(
            style: .success,
            title: "What Is This Fee?",
            subtitle: "The account you're trying to withdraw to requires a one time account creation fee. This fee will be deducted from the amount you're withdrawing",
            dismissable: true
        ) {
            .okay(kind: .standard)
        }
    }
}
