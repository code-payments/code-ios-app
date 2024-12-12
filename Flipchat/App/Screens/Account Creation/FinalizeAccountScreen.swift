//
//  FinalizeAccountScreen.swift
//  Flipchat
//
//  Created by Dima Bart on 2021-04-13.
//

import SwiftUI
import CodeUI
import FlipchatServices

struct FinalizeAccountScreen: View {
    
    @ObservedObject private var viewModel: OnboardingViewModel
    
    // MARK: - Init -
    
    init(viewModel: OnboardingViewModel) {
        self.viewModel = viewModel
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                Spacer()
                
                VStack(spacing: 60) {
                    DeterministicAvatar(
                        data: viewModel.owner.publicKey.data,
                        diameter: 120
                    )
                    
                    VStack(spacing: 10) {
                        Text("Finalize account creation")
                            .font(.appTextLarge)
                            .foregroundStyle(Color.textMain)
                        Text("Accounts on Flipchat must be purchased for $0.99 to reduce spam")
                            .font(.appTextMedium)
                            .foregroundStyle(Color.textSecondary)
                            .padding(.horizontal, 20)
                    }
                    .multilineTextAlignment(.center)
                }
                .padding(.bottom, 44) // Navbar offset
                
                Spacer()
                
                CodeButton(
                    state: viewModel.paymentButtonState,
                    style: .filled,
                    title: "Purchase Your Account"
                ) {
                    try? viewModel.payForCreateAccount()
                }
            }
            .ignoresSafeArea(.keyboard)
            .foregroundColor(.textMain)
            .padding(20)
            .navigationBarTitle(Text(""), displayMode: .inline)
        }
    }
}

// MARK: - Previews -

#Preview {
    FinalizeAccountScreen(
        viewModel: .init(
            chatID: .mock,
            session: .mock,
            client: .mock,
            flipClient: .mock,
            chatController: .mock,
            banners: .mock,
            isPresenting: .constant(true)
        )
    )
}
