//
//  BuyAccountScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-04-13.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct BuyAccountScreen: View {
    
    @ObservedObject private var viewModel: OnboardingViewModel
    @ObservedObject private var storeController: StoreController
    
    private var formattedPrice: String? {
        storeController.products[IAPProduct.createAccountWithWelcomeBonus.rawValue]?.formattedPrice
    }
    
    private var isPriceAvailable: Bool {
        formattedPrice != nil
    }
    
    // MARK: - Init -
    
    init(viewModel: OnboardingViewModel) {
        self.viewModel = viewModel
        self.storeController = viewModel.storeController
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 20) {
                Spacer()
                
                VStack(alignment: .center, spacing: 60) {
                    Image.asset(.successCheckmark)
                        .padding(.bottom, 20)
                    
                    if let formattedPrice {
                        descriptions(formattedPrice: formattedPrice)
                    } else {
                        descriptions(formattedPrice: "$19")
                            .opacity(0)
                            .overlay {
                                LoadingView(color: .textMain)
                            }
                    }
                }
                .foregroundColor(.textMain)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
                
                Spacer()
                
                CodeButton(
                    state: viewModel.buyAccountButtonState,
                    style: .filled,
                    title: "Buy Account",
                    disabled: !isPriceAvailable,
                    action: viewModel.buyAccountAction
                )
            }
            .ignoresSafeArea(.keyboard)
            .foregroundColor(.textMain)
            .padding(20)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
        .dialog(item: $viewModel.dialogItem)
    }
    
    @ViewBuilder private func descriptions(formattedPrice: String) -> some View {
        VStack(alignment: .center, spacing: 40) {
            Text("Pay \(formattedPrice), Get \(formattedPrice)")
                .font(.appTextLarge)
            
            Text("For a limited time new accounts will receive a free welcome bonus of \(formattedPrice) of stablecoins.")
                .font(.appTextSmall)
        }
    }
    
    // MARK: - Copy / Paste -
    
    private func copy() {
        UIPasteboard.general.string = viewModel.inflightMnemonic.phrase
    }
}
