//
//  IntroScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-01-15.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct IntroScreen: View {
    
    @EnvironmentObject private var sessionAuthenticator: SessionAuthenticator
    
    @State private var isShowingLogin          = false
    @State private var isShowingPrivacyPolicy  = false
    @State private var isShowingTermsOfService = false
    
    @StateObject private var viewModel: OnboardingViewModel
    
    // MARK: - Init -
    
    init(container: Container) {
        _viewModel = StateObject(wrappedValue: OnboardingViewModel(container: container))
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
                            
                            CodeButton(
                                style: .subtle,
                                title: "Log In",
                                action: viewModel.loginAction
                            )
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
                    .foregroundColor(.textSecondary)
                    .font(.appTextHeading)
                    .opacity(0.5)
                    .padding(30)
                }
            }
            .ignoresSafeArea(.keyboard)
            .navigationBarTitle("")
            .navigationBarHidden(true)
            .navigationDestination(for: OnboardingPath.self) { path in
                switch path {
                case .login:
                    LoginScreen()
                case .accessKey:
                    AccessKeyScreen(viewModel: viewModel)
                case .buyAccount:
                    BuyAccountScreen(viewModel: viewModel)
                case .cameraAccess:
                    PermissionScreen.forCameraAccess(
                        action: viewModel.allowCameraAccessAction
                    )
                case .purchasePending:
                    PurchasePendingScreen()
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Previews -

#Preview {
    IntroScreen(container: .mock)
}
