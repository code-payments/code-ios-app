//
//  IntroScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-01-15.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// Thin environment-reading wrapper that hands the container to
/// ``IntroScreenContent``, whose `init` builds the `@State` onboarding view
/// model synchronously. The `Container` is injected app-wide, so it is
/// available here on the logged-out path.
struct IntroScreen: View {

    @Environment(Container.self) private var container

    var body: some View {
        IntroScreenContent(container: container)
    }
}

private struct IntroScreenContent: View {

    @Environment(SessionAuthenticator.self) private var sessionAuthenticator

    @State private var isShowingPrivacyPolicy  = false
    @State private var isShowingTermsOfService = false

    @State private var viewModel: OnboardingViewModel

    // MARK: - Init -

    init(container: Container) {
        self.viewModel = OnboardingViewModel(container: container)
    }
    
    // MARK: - Body -
    
    /// An account is waiting on its resumed step, so the intro would only flash before it.
    /// Rendering this instead keeps the stack uncreated until the path is seeded, which lets
    /// the first resumed screen appear without a push animation.
    private var isAwaitingResume: Bool {
        sessionAuthenticator.pendingOnboarding != nil && viewModel.path.isEmpty
    }

    var body: some View {
        if isAwaitingResume {
            Background(color: .backgroundMain) {
                LoadingView(color: .white)
            }
            .task(id: sessionAuthenticator.pendingOnboarding?.keyAccount.ownerPublicKey.base58, resumeIfPending)
        } else {
            introStack
        }
    }

    private func resumeIfPending() async {
        guard let account = sessionAuthenticator.pendingOnboarding else { return }
        await viewModel.resumeOnboarding(with: account)
    }

    private var introStack: some View {
        NavigationStack(path: $viewModel.path) {
            Background(color: .backgroundMain) {
                VStack {
                    VStack(spacing: 10) {
                        Spacer()
                        
                        VStack(spacing: 20) {
                            Image.asset(.flipcashBrand)
                        }
                        
                        Spacer()
                        
                        VStack(spacing: 5) {
                            CodeButton(
                                state: sessionAuthenticator.loginButtonState,
                                style: .filled,
                                title: "Create a New Account",
                                action: viewModel.createAccountAction
                            )
                            
                            Button("Log In", action: viewModel.loginAction)
                                .buttonStyle(.subtle)
                        }
                    }
                    .padding(20.0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    
                    VStack(spacing: 0) {
                        Text("By tapping any button above you agree to our")
                        HStack(spacing: 3) {
                            Button {
                                isShowingTermsOfService.toggle()
                            } label: {
                                Text("Terms of Service")
                                    .underline()
                            }
                            .sheet(isPresented: $isShowingTermsOfService) {
                                SafariView(
                                    url: .termsOfService,
                                    entersReaderIfAvailable: false
                                )
                            }
                            Text("and")
                            Button {
                                isShowingPrivacyPolicy.toggle()
                            } label: {
                                Text("Privacy Policy")
                                    .underline()
                            }
                            .sheet(isPresented: $isShowingPrivacyPolicy) {
                                SafariView(
                                    url: .privacyPolicy,
                                    entersReaderIfAvailable: false
                                )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.textSecondary)
                    .font(.appTextHeading)
                    .opacity(0.5)
                    .padding(30)
                }
            }
            .ignoresSafeArea(.keyboard)
            .navigationTitle("")
            .toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(for: OnboardingPath.self) { path in
                switch path {
                case .accountSelection:
                    AccountSelectionScreen(
                        sessionAuthenticator: sessionAuthenticator,
                        action: viewModel.recoverExistingAccount,
                        onEnterDifferentKey: {
                            viewModel.path.append(.login)
                        }
                    )
                case .login:
                    LoginScreen()
                case .accessKey:
                    AccessKeyScreen(viewModel: viewModel)
                        .navigationBarBackButtonHidden(viewModel.hidesBackButton(for: .accessKey))
                case .accessKeyHelp:
                    AccessKeyHelpScreen()
                case .pushNotifications:
                    NotificationPermissionScreen(viewModel: viewModel)
                        .navigationBarBackButtonHidden(viewModel.hidesBackButton(for: .pushNotifications))
                case .pushNotificationsDenied:
                    NotificationPermissionDeniedScreen(viewModel: viewModel)
                        .navigationBarBackButtonHidden(viewModel.hidesBackButton(for: .pushNotificationsDenied))
                case .displayName:
                    if let nameVM = viewModel.nameViewModel {
                        OnboardingNameScreen(viewModel: nameVM)
                            .navigationBarBackButtonHidden(viewModel.hidesBackButton(for: .displayName))
                    }
                }
            }
        }
        .task(id: sessionAuthenticator.pendingOnboarding?.keyAccount.ownerPublicKey.base58, resumeIfPending)
    }
}

// MARK: - Previews -

#Preview {
    IntroScreen()
        .injectingEnvironment(from: .mock)
}
