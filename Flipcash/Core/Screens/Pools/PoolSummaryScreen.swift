//
//  PoolSummaryScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-06-18.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct PoolSummaryScreen: View {
    
    @ObservedObject private var viewModel: PoolViewModel
    
    // MARK: - Init -
    
    init(viewModel: PoolViewModel) {
        self.viewModel = viewModel
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack {
                Spacer()
                
                VStack(spacing: 40) {
                    Text(viewModel.enteredPoolName)
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)
                    
                    if let poolBuyIn = viewModel.enteredPoolFiat?.converted {
                        BorderedContainer {
                            VStack(spacing: 10) {
                                AmountText(
                                    flagStyle: poolBuyIn.currencyCode.flagStyle,
                                    content: poolBuyIn.formatted(suffix: nil),
                                    showChevron: false,
                                    canScale: false
                                )
                                .font(.appDisplayMedium)
                                
                                Text("Pool Buy In")
                                    .font(.appTextMedium)
                                    .foregroundStyle(Color.textSecondary)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 30)
                        }
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                VStack(spacing: 25) {
                    Text("As the pool host, you will decide the outcome of the pool in your sole discretion")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                    
                    CodeButton(
                        state: viewModel.createPoolButtonState,
                        style: .filled,
                        title: "Create Pool",
                        disabled: !viewModel.canCreatePool,
                        action: viewModel.createPoolAction
                    )
                }
            }
            .multilineTextAlignment(.center)
            .padding(20)
        }
        .navigationTitle("Create Pool")
        .navigationBarTitleDisplayMode(.inline)
    }
}
