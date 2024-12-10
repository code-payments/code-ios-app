//
//  CreateAccountScreen.swift
//  Flipchat
//
//  Created by Dima Bart on 2021-04-13.
//

import SwiftUI
import CodeUI
import FlipchatServices

struct CreateAccountScreen: View {
    
    @Binding var isPresented: Bool
    
    @StateObject private var viewModel: OnboardingViewModel
    
    // MARK: - Init -
    
    init(isPresented: Binding<Bool>, sessionAuthenticator: SessionAuthenticator, banners: Banners) {
        self._isPresented = isPresented
        
        let viewModel = OnboardingViewModel(sessionAuthenticator: sessionAuthenticator, banners: banners)
        viewModel.generateNewSeed()
        
        self._viewModel = StateObject(
            wrappedValue: viewModel
        )
    }
    
    // MARK: - Body -
    
    var body: some View {
        NavigationStack(path: $viewModel.navigationPath) {
            Background(color: .backgroundMain) {
                VStack(spacing: 0) {
                    Spacer()
                    
                    VStack(spacing: 60) {
                        DeterministicAvatar(
                            data: viewModel.ownerForMnemonic.publicKey.data,
                            diameter: 120
                        )
                        
                        VStack(spacing: 10) {
                            Text("Create an account to join rooms")
                                .font(.appTextLarge)
                                .foregroundStyle(Color.textMain)
                            Text("New accounts cost $0.99")
                                .font(.appTextMedium)
                                .foregroundStyle(Color.textSecondary)
                                .padding(.horizontal, 20)
                        }
                        .multilineTextAlignment(.center)
                    }
                    .padding(.bottom, 44) // Navbar offset
                    
                    Spacer()
                    
                    CodeButton(
                        state: viewModel.accessKeyButtonState,
                        style: .filled,
                        title: "Get Started"
                    ) {
                        viewModel.getStarted()
                    }
                    
                    CodeButton(
                        style: .subtle,
                        title: "Not Now",
                        disabled: viewModel.accessKeyButtonState != .normal
                    ) {
                        isPresented = false
                    }
                }
                .ignoresSafeArea(.keyboard)
                .foregroundColor(.textMain)
                .padding(20)
                .navigationBarTitle(Text(""), displayMode: .inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ToolbarCloseButton(binding: $isPresented)
                    }
                }
            }
            .navigationDestination(for: OnboardingViewModel.NavPath.self) { path in
                switch path {
                case .enterName:
                    EnterNameScreen(viewModel: viewModel)
                case .accessKey:
                    AccessKeyScreen(viewModel: viewModel)
                case .finalizeCreation:
                    FinalizeAccountScreen(viewModel: viewModel)
                }
            }
        }
    }
}

// MARK: - Previews -

#Preview {
    CreateAccountScreen(
        isPresented: .constant(true),
        sessionAuthenticator: .mock,
        banners: .mock
    )
}
