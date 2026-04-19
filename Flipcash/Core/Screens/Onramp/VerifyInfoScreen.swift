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

    @Bindable private var coordinator: OnrampCoordinator

    // MARK: - Init -

    init(coordinator: OnrampCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: - Body -

    var body: some View {
        NavigationStack(path: $coordinator.verificationPath) {
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
                        coordinator.navigateToInitialVerification()
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
                    ToolbarCloseButton(binding: $coordinator.isShowingVerificationFlow)
                }
            }
            .navigationDestination(for: OnrampVerificationPath.self) { path in
                switch path {
                case .info:
                    VerifyInfoScreen(coordinator: coordinator)
                case .enterPhoneNumber:
                    EnterPhoneScreen(coordinator: coordinator)
                        .interactiveDismissDisabled()
                case .confirmPhoneNumberCode:
                    ConfirmPhoneScreen(coordinator: coordinator)
                        .interactiveDismissDisabled()
                case .enterEmail:
                    EnterEmailScreen(coordinator: coordinator)
                        .interactiveDismissDisabled()
                case .confirmEmailCode:
                    ConfirmEmailScreen(coordinator: coordinator)
                        .interactiveDismissDisabled()
                }
            }
            .ignoresSafeArea(.keyboard)
        }
    }
}
