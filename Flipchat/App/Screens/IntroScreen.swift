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
    
    @State private var isShowingPrivacyPolicy  = false
    @State private var isShowingTermsOfService = false
    
    // MARK: - Init -
    
    init() {}
    
    // MARK: - Body -
    
    var body: some View {
        NavigationView {
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
                                title: Localized.Action.createAccount
                            ) {
                                // Create account flow
                            }
                            
                            CodeButton(style: .subtle, title: Localized.Action.logIn) {
                                // Login flow
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
                                isShowingTermsOfService.toggle()
                            } label: {
                                Text(Localized.Title.termsOfService)
                                    .underline()
                            }
                            .sheet(isPresented: $isShowingTermsOfService) {
                                SafariView(
                                    url: .termsOfService,
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
}

// MARK: - Previews -

#Preview {
    Group {
        IntroScreen()
    }
    .environmentObjectsForSession()
}