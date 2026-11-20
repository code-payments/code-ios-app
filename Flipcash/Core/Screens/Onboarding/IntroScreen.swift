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
    @Environment(\.colorScheme) private var colorScheme

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
                LoadingView(color: .textMain)
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

    /// An empty bar collapses, which lifts a step without a back button above one that has it.
    private func barVisibility(for step: OnboardingPath) -> Visibility {
        viewModel.keepsNavigationBarRow(for: step) ? .visible : .automatic
    }

    private var introStack: some View {
        NavigationStack(path: $viewModel.path) {
            Background(color: .backgroundMain) {
                VStack {
                    VStack(spacing: 10) {
                        Spacer()
                        
                        VStack(spacing: 20) {
                            Image.asset(.flipcashBrand)
                                .renderingMode(.template)
                                .foregroundStyle(Color.textMain)
                        }
                        
                        Spacer()
                        
                        VStack(spacing: Metrics.buttonGap) {
                            Button(action: viewModel.createAccountAction) {
                                ButtonStateLabel("Create a New Account", state: sessionAuthenticator.loginButtonState)
                            }
                            .buttonStyle(.filled)
                            .disabled(!sessionAuthenticator.loginButtonState.isNormal)
                            
                            Button("Log In", action: viewModel.loginAction)
                                .buttonStyle(.textLink)
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
                    .opacity(colorScheme.legalFooterOpacity)
                    .padding(30)
                }
            }
            .ignoresSafeArea(.keyboard)
            .navigationTitle("")
            .toolbarVisibility(.hidden, for: .navigationBar)
            .dialog(item: $viewModel.introDialogItem)
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
                case .enterPhoneNumber:
                    if let phoneVM = viewModel.phoneViewModel {
                        EnterPhoneScreen(viewModel: phoneVM, copy: .onboarding)
                            .navigationBarBackButtonHidden(viewModel.hidesBackButton(for: .enterPhoneNumber))
                            .toolbarVisibility(barVisibility(for: .enterPhoneNumber), for: .navigationBar)
                    }
                case .confirmPhoneNumberCode:
                    if let phoneVM = viewModel.phoneViewModel {
                        ConfirmPhoneScreen(viewModel: phoneVM, copy: .onboarding)
                            .navigationBarBackButtonHidden(viewModel.hidesBackButton(for: .confirmPhoneNumberCode))
                            .toolbarVisibility(barVisibility(for: .confirmPhoneNumberCode), for: .navigationBar)
                    }
                case .email:
                    if let emailVM = viewModel.emailViewModel {
                        OnboardingEmailScreen(viewModel: emailVM)
                            .navigationBarBackButtonHidden(viewModel.hidesBackButton(for: .email))
                            .toolbarVisibility(barVisibility(for: .email), for: .navigationBar)
                    }
                case .displayName:
                    if let nameVM = viewModel.nameViewModel {
                        OnboardingNameScreen(viewModel: nameVM, copy: viewModel.nameCopy)
                            .navigationBarBackButtonHidden(viewModel.hidesBackButton(for: .displayName))
                            .toolbarVisibility(barVisibility(for: .displayName), for: .navigationBar)
                    }
                }
            }
        }
        .task(id: sessionAuthenticator.pendingOnboarding?.keyAccount.ownerPublicKey.base58, resumeIfPending)
    }
}

private extension ColorScheme {

    /// The legal footer's strength over `textSecondary`: half in dark, as designed, and whole in
    /// light, where half of `textSecondary` on white falls to 2:1.
    var legalFooterOpacity: Double {
        switch self {
        case .dark: 0.5
        case .light: 1
        @unknown default: 1
        }
    }
}

// MARK: - Previews -

#Preview {
    IntroScreen()
        .injectingEnvironment(from: .mock)
}
