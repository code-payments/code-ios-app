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
    
    var body: some View {
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
                case .accessKeyHelp:
                    AccessKeyHelpScreen()
                case .pushNotifications:
                    NotificationPermissionScreen(viewModel: viewModel)
                case .pushNotificationsDenied:
                    NotificationPermissionDeniedScreen(viewModel: viewModel)
                case .phoneVerification:
                    OnboardingPhoneVerificationStep(viewModel: viewModel)
                case .confirmPhoneNumberCode:
                    if let phoneVM = viewModel.phoneVerificationViewModel {
                        ConfirmPhoneScreen(viewModel: phoneVM)
                            .navigationTitle("Connect Phone Number")
                            .navigationBarBackButtonHidden(true)
                    }
                }
            }
        }
    }
}

// MARK: - Phone verification step -

/// Wrapper for the onboarding phone entry screen. Reads the shared
/// `PhoneVerificationViewModel` from `OnboardingViewModel` so the
/// follow-up `ConfirmPhoneScreen` destination binds the same instance.
private struct OnboardingPhoneVerificationStep: View {

    let viewModel: OnboardingViewModel

    var body: some View {
        if let phoneVM = viewModel.phoneVerificationViewModel {
            EnterPhoneScreen(viewModel: phoneVM)
                .navigationTitle("Connect Phone Number")
                .navigationBarBackButtonHidden(true)
        }
    }
}

// MARK: - Previews -

#Preview {
    IntroScreen()
        .injectingEnvironment(from: .mock)
}
