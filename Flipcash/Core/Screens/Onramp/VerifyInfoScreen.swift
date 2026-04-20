//
//  VerifyInfoScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-03-02.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct VerifyInfoScreen: View {

    @Bindable private var onrampCoordinator: OnrampCoordinator

    // MARK: - Init -

    init(onrampCoordinator: OnrampCoordinator) {
        self.onrampCoordinator = onrampCoordinator
    }

    // MARK: - Body -

    var body: some View {
        NavigationStack(path: $onrampCoordinator.verificationPath) {
            Background(color: .backgroundMain) {
                VStack(alignment: .center, spacing: 20) {
                    Spacer()

                    VStack(spacing: 20) {
                        Image.asset(.verifyIdentity)

                        Text("Verify Your Phone Number and Email to Continue")
                            .font(.appTextLarge)
                            .foregroundStyle(Color.textMain)

                        Text("This will allow you to add funds from your debit card")
                            .foregroundStyle(Color.textSecondary)
                            .font(.appTextMedium)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20) // Additional 20pts

                    Spacer()

                    Button("Next") {
                        onrampCoordinator.navigateToInitialVerification()
                    }
                    .buttonStyle(.filled)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarCloseButton(binding: $onrampCoordinator.isShowingVerificationFlow)
                }
            }
            .navigationDestination(for: OnrampVerificationPath.self) { path in
                switch path {
                case .info:
                    VerifyInfoScreen(onrampCoordinator: onrampCoordinator)
                case .enterPhoneNumber:
                    EnterPhoneScreen(onrampCoordinator: onrampCoordinator)
                        .interactiveDismissDisabled()
                case .confirmPhoneNumberCode:
                    ConfirmPhoneScreen(onrampCoordinator: onrampCoordinator)
                        .interactiveDismissDisabled()
                case .enterEmail:
                    EnterEmailScreen(onrampCoordinator: onrampCoordinator)
                        .interactiveDismissDisabled()
                case .confirmEmailCode:
                    ConfirmEmailScreen(onrampCoordinator: onrampCoordinator)
                        .interactiveDismissDisabled()
                }
            }
            .ignoresSafeArea(.keyboard)
        }
    }
}
