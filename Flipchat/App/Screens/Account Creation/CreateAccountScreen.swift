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
    
    @StateObject private var viewModel: OnboardingViewModel
    
    // MARK: - Init -
    
    init(viewModel: @autoclosure @escaping () -> OnboardingViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel())
    }
    
    // MARK: - Body -
    
    var body: some View {
        NavigationStack(path: $viewModel.navigationPath) {
            Background(color: .backgroundMain) {
                VStack(spacing: 0) {
                    Spacer()
                    
                    VStack(spacing: 60) {
                        DeterministicAvatar(
                            data: viewModel.owner.publicKey.data,
                            diameter: 120
                        )
                        
                        VStack(spacing: 10) {
                            Text("Create an Account to Join Rooms")
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
                        viewModel.dismiss()
                    }
                }
                .ignoresSafeArea(.keyboard)
                .foregroundColor(.textMain)
                .padding(20)
                .navigationBarTitle(Text(""), displayMode: .inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ToolbarCloseButton { viewModel.dismiss() }
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
        viewModel: .init(
            chatID: .mock,
            hostID: .mock,
            cover: 100,
            session: .mock,
            client: .mock,
            flipClient: .mock,
            chatController: .mock,
            chatViewModel: .mock,
            banners: .mock,
            isPresenting: .constant(true)
        )
    )
}
