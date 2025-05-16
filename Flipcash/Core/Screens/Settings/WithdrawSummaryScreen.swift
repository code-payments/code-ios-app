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
                    
                    BorderedContainer {
                        VStack(spacing: 10) {
                            AmountText(
                                flagStyle: viewModel.enteredFiat?.converted.currencyCode.flagStyle ?? .fiat(.us),
                                content: viewModel.enteredFiat?.converted.formatted(suffix: nil) ?? "$0.00",
                                showChevron: false
                            )
                            .font(.appDisplayMedium)
                        }
                        .padding(20)
                        .frame(height: geometry.size.height * 0.3)
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
    }
}
