//
//  IntroScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-01-15.
//

import SwiftUI
import CodeUI
import FlipchatServices

struct IntroScreen: View {
    
    @EnvironmentObject private var client: Client
    @EnvironmentObject private var cameraAuthorizer: CameraAuthorizer
    
    @State private var isShowingPrivacyPolicy  = false
    @State private var isShowingTermsOfService = false
    
    @StateObject private var viewModel: OnboardingViewModel
    
    private let sessionAuthenticator: SessionAuthenticator
    private let banners: Banners
    
    // MARK: - Init -
    
    init(sessionAuthenticator: SessionAuthenticator, banners: Banners) {
        self.sessionAuthenticator = sessionAuthenticator
        self.banners = banners
        self._viewModel = StateObject(
            wrappedValue: OnboardingViewModel(sessionAuthenticator: sessionAuthenticator, banners: banners)
        )
    }
    
    // MARK: - Body -
    
    var body: some View {
        NavigationStack(path: $viewModel.navigationPath) {
            Background(color: .backgroundMain) {
                VStack {
                    VStack(spacing: 10) {
                        Spacer()
                        
                        VStack(spacing: 20) {
                            Image(with: .brandLarge)
                            Text("Flipchat")
                                .font(.appDisplayMedium)
                                .foregroundStyle(Color.textMain)
                        }
                        
                        Spacer()
                        
                        VStack(spacing: 5) {
                            CodeButton(
                                isLoading: sessionAuthenticator.inProgress,
                                style: .filled,
                                title: Localized.Action.createAccount,
                                action: viewModel.startCreateAccount
                            )
                            
                            CodeButton(
                                style: .subtle,
                                title: Localized.Action.logIn,
                                action: viewModel.startLogin
                            )
                        }
                    }
                    .padding(20.0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    
                    VStack(spacing: 0) {
                        Text(Localized.Login.Description.byTapping)
                        HStack(spacing: 3) {
                            Text(Localized.Login.Description.agreeToOur)
                            Button {
                                isShowingTermsOfService.toggle()
                            } label: {
                                Text(Localized.Title.termsOfService)
                                    .underline()
                            }
                            .sheet(isPresented: $isShowingTermsOfService) {
                                SafariView(
                                    url: .flipchatTermsOfService,
                                    entersReaderIfAvailable: false
                                )
                            }
                            Text(Localized.Core.and)
                            Button {
                                isShowingPrivacyPolicy.toggle()
                            } label: {
                                Text(Localized.Title.privacyPolicy)
                                    .underline()
                            }
                            .sheet(isPresented: $isShowingPrivacyPolicy) {
                                SafariView(
                                    url: .flipchatPrivacyPolicy,
                                    entersReaderIfAvailable: false
                                )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundColor(.textSecondary)
                    .font(.appTextHeading)
                    .opacity(0.5)
                    .padding(30)
                }
            }
            .ignoresSafeArea(.keyboard)
            .navigationBarTitle("")
            .navigationBarHidden(true)
            .navigationDestination(for: OnboardingViewModel.NavPath.self) { path in
                switch path {
                case .enterName:
                    EnterNameScreen(viewModel: viewModel)
                case .login:
                    LoginScreen()
                case .permissionPush:
                    PushPermissionsScreen(viewModel: viewModel)
                case .accessKey:
                    AccessKeyScreen(viewModel: viewModel)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
    
    // MARK: - Actions -
    
    private func openCode() {
        let scheme = URL.codeScheme()
        if scheme.canOpen() {
            scheme.openWithApplication()
        } else {
            URL.downloadCode.openWithApplication()
        }
    }
}

// MARK: - Previews -

#Preview {
    Group {
        IntroScreen(sessionAuthenticator: .mock, banners: .mock)
    }
    .environmentObjectsForSession()
}
