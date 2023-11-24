//
//  IntroScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-01-15.
//

import SwiftUI
import CodeServices
import CodeUI

struct IntroScreen: View {
    
    @EnvironmentObject private var client: Client
    @EnvironmentObject private var bannerController: BannerController
    @EnvironmentObject private var sessionAuthenticator: SessionAuthenticator
    @EnvironmentObject private var cameraAuthorizer: CameraAuthorizer
    
    @StateObject private var viewModel: IntroViewModel
    
    // MARK: - Init -
    
    init(viewModel: @autoclosure @escaping () -> IntroViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel())
    }
    
    // MARK: - Body -
    
    var body: some View {
        NavigationView {
            Background(gradient: .background) {
                VStack {
                    Flow(isActive: $viewModel.isShowingLoginScreen) {
                        LoginScreen(isActive: $viewModel.isShowingLoginScreen)
                    }
                    
                    Flow(isActive: $viewModel.isShowingPhoneVerificationScreen) {
                        VerifyPhoneScreen(
                            isActive: $viewModel.isShowingPhoneVerificationScreen,
                            showCloseButton: false,
                            viewModel: VerifyPhoneViewModel(
                                client: client,
                                bannerController: bannerController,
                                mnemonic: viewModel.inflighMnemonic,
                                completion: viewModel.completePhoneVerificationForAccountCreation
                            )
                        ) {
                            Flow(isActive: $viewModel.isShowingSecretRecoveryScreen) {
                                LazyView(
                                    AccessKeyScreen(viewModel: viewModel) {
                                        Flow(isActive: $viewModel.isShowingCameraPermissionsScreen) {
                                            cameraPermissionsScreen {}
                                        }
                                        
                                        Flow(isActive: $viewModel.isShowingPushPermissionsScreen) {
                                            pushPermissionsScreen {
                                                Flow(isActive: $viewModel.isShowingCameraPermissionsAfterPushScreen) {
                                                    cameraPermissionsScreen {}
                                                }
                                            }
                                        }
                                    }
                                )
                            }
                        }
                    }
                    
                    VStack(spacing: 10) {
                        Spacer()
                        
                        CodeBrand(size: .large)
                            .padding(.trailing, 10) // For visual center
                        
                        Spacer()
                        
                        VStack(spacing: 5) {
                            CodeButton(
                                isLoading: sessionAuthenticator.inProgress,
                                style: .filled,
                                title: Localized.Action.createAccount
                            ) {
                                viewModel.startAccountCreation()
                            }
                            
                            CodeButton(style: .subtle, title: Localized.Action.logIn) {
                                viewModel.startLogin()
                            }
                        }
                    }
                    .padding(20.0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    
                    VStack(spacing: 0) {
                        Text(Localized.Login.Description.byTapping)
                        HStack(spacing: 3) {
                            Text(Localized.Login.Description.agreeToOur)
                            Button {
                                viewModel.showTermsOfService()
                            } label: {
                                Text(Localized.Title.termsOfService)
                                    .underline()
                            }
                            .sheet(isPresented: $viewModel.isShowingTermsOfService) {
                                SafariView(
                                    url: .termsOfService,
                                    entersReaderIfAvailable: false
                                )
                            }
                            Text(Localized.Core.and)
                            Button {
                                viewModel.showPrivacyPolicy()
                            } label: {
                                Text(Localized.Title.privacyPolicy)
                                    .underline()
                            }
                            .sheet(isPresented: $viewModel.isShowingPrivacyPolicy) {
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
        }
        .navigationViewStyle(.stack)
    }
    
    @ViewBuilder private func cameraPermissionsScreen<Content>(@ViewBuilder content: @escaping () -> Content) -> some View where Content: View {
        VStack {
            content()
            PermissionScreen.forCameraAccess {
                viewModel.promptCameraAccess()
            }
            .navigationBarBackButtonHidden(true)
        }
    }
    
    @ViewBuilder private func pushPermissionsScreen<Content>(@ViewBuilder content: @escaping () -> Content) -> some View where Content: View {
        VStack {
            content()
            PermissionScreen.forPushNotifications {
                viewModel.promptPushAccess()
            } skipAction: {
                viewModel.skipPushAccess()
            }
            .navigationBarBackButtonHidden(true)
        }
    }
}

// MARK: - Previews -

struct IntroScreen_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            IntroScreen(viewModel: IntroViewModel(container: .mock))
            IntroScreen(viewModel: IntroViewModel(container: .mock))
                .previewLayout(.fixed(width: 390, height: 600))
            IntroScreen(viewModel: IntroViewModel(container: .mock))
                .previewLayout(.fixed(width: 320, height: 900))
        }
        .environmentObjectsForSession()
    }
}
