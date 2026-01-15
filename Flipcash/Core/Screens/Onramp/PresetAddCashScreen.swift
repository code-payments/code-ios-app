//
//  AddCashScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-03-02.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct PresetAddCashScreen: View {
    
    @Binding var isPresented: Bool
    
    @ObservedObject private var viewModel: OnrampViewModel
    
    private let container: Container
    private let session: Session
    
    // MARK: - Init -
    
    init(isPresented: Binding<Bool>, container: Container, sessionContainer: SessionContainer) {
        self._isPresented = isPresented
        self.container    = container
        self.session      = sessionContainer.session
        self.viewModel    = sessionContainer.onrampViewModel
    }
    
    // MARK: - Body -
    
    var body: some View {
        NavigationStack {
            Background(color: .backgroundMain) {
                VStack(alignment: .center, spacing: 20) {
                    GridAmounts(selected: viewModel.adjustingSelectedPreset) { action in
                        switch action {
                        case .amount(let amount):
                            let fiat = try! Quarks(
                                fiatInt: amount,
                                currencyCode: .usd,
                                decimals: PublicKey.usdf.mintDecimals
                            )
                            Analytics.onrampAmountPresetSelected(amount: fiat)
                        case .more:
                            viewModel.customAmountAction()
                        }
                    }
                    .disabled(viewModel.payButtonState == .loading)
                    .padding(.bottom, 10)
                    
                    CodeButton(
                        state: viewModel.payButtonState,
                        style: .filledApplePay,
                        title: "Add",
                        disabled: !viewModel.hasSelectedAmount,
                        action: viewModel.addWithApplePayAction
                    )
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
                .navigationTitle("Add Cash With Debit Card")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ToolbarCloseButton(binding: $isPresented)
                    }
                }
                .ignoresSafeArea(.keyboard)
            }
            .overlay {
                viewModel.applePayWebView()
            }
            .sheet(isPresented: $viewModel.isShowingVerificationFlow) {
                VerifyInfoScreen(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.isShowingAmountEntryScreen) {
                OnrampAmountScreen(viewModel: viewModel)
            }
        }
        .frame(height: 320)
    }
}
