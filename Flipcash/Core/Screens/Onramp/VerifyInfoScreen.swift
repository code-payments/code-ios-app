//
//  VerifyInfoScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-03-02.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct VerifyInfoScreen: View {
    
    @ObservedObject private var viewModel: OnrampViewModel
    
    // MARK: - Init -
    
    init(viewModel: OnrampViewModel) {
        self.viewModel = viewModel
    }
    
    // MARK: - Body -
    
    var body: some View {
        NavigationStack(path: $viewModel.onrampPath) {
            Background(color: .backgroundMain) {
                VStack(alignment: .center, spacing: 20) {
                    Spacer()
                    
                    VStack(spacing: 20) {
                        Image.asset(.verifyIdentity)
                        
                        Text("Verify Your Phone Number and Email to Continue")
                            .font(.appTextLarge)
                            .foregroundStyle(Color.textMain)
                        
                        Text("This will allow you to add funds from your debit card")
                            .foregroundStyle(Color.textSecondary)
                            .font(.appTextMedium)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20) // Additional 20pts
                    
                    Spacer()
                    
                    CodeButton(
                        style: .filled,
                        title: "Next"
                    ) {
                        viewModel.navigateToInitialVerification()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarCloseButton(binding: $viewModel.isShowingVerificationFlow)
                }
            }
            .navigationDestination(for: OnrampPath.self) { path in
                switch path {
                case .info:
                    VerifyInfoScreen(viewModel: viewModel)
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
                case .success:
                    OnrampSuccessScreen(viewModel: viewModel)
                        .interactiveDismissDisabled()
                }
            }
            .ignoresSafeArea(.keyboard)
        }
    }
}
