//
//  AddCashScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-03-02.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct AddCashScreen: View {
    
    @Binding var isPresented: Bool
    
    @State private var isShowingDeposit: Bool = false
    
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
        NavigationStack(path: $viewModel.onrampPath) {
            Background(color: .backgroundMain) {
                VStack(alignment: .center, spacing: 20) {
                    Spacer()
                    
                    VStack(spacing: 60) {
                        
                        // Header
                        VStack(spacing: 30) {
                            Image.asset(.depositCircle)
                            
                            Text("Add cash to your Flipcash wallet")
                                .font(.appTextMedium)
                                .foregroundColor(.textSecondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        // Buttons
                        VStack(spacing: 15) {
                            BorderedButton(
                                image: .asset(.debitCard),
                                title: "Debit Card with Apple Pay",
                                subtitle: "Add cash to your wallet from your debit card",
                                action: viewModel.addCashWithDebitCardAction
                            )
                            
                            BorderedButton(
                                image: .asset(.debitWallet),
                                title: "Crypto Wallet",
                                subtitle: "Deposit USDC from your crypto wallet"
                            ) {
                                
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .navigationTitle("Add Cash")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarCloseButton(binding: $isPresented)
                }
            }
            .navigationDestination(for: OnrampPath.self) { path in
                switch path {
                case .enterPhoneNumber:
                    EnterPhoneScreen(viewModel: viewModel)
                        .interactiveDismissDisabled()
                case .confirmPhoneNumberCode:
                    ConfirmPhoneScreen(viewModel: viewModel)
                        .interactiveDismissDisabled()
                case .enterEmail:
                    EnterEmailScreen(viewModel: viewModel)
                        .interactiveDismissDisabled()
                case .confirmEmailCode:
                    ConfirmEmailScreen(viewModel: viewModel)
                        .interactiveDismissDisabled()
                case .enterAmount:
                    OnrampAmountScreen(viewModel: viewModel)
                        .interactiveDismissDisabled()
                }
            }
            .ignoresSafeArea(.keyboard)
        }
    }
}
