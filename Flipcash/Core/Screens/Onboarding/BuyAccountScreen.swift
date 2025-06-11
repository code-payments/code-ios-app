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
        storeController.products[IAPProduct.createAccount.rawValue]?.displayPrice
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
                        descriptions(formattedPrice: "$0.99")
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
                    title: "Purchase Your Account",
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
        .task {
            storeController.loadProductsIfNeeded()
        }
    }
    
    @ViewBuilder private func descriptions(formattedPrice: String) -> some View {
        VStack(alignment: .center, spacing: 40) {
            Text("Purchase an Account for \(formattedPrice)")
                .font(.appTextLarge)
            
            Text("This fee is used to cover our operational costs")
                .font(.appTextSmall)
        }
    }
    
    // MARK: - Copy / Paste -
    
    private func copy() {
        UIPasteboard.general.string = viewModel.inflightMnemonic.phrase
    }
}
