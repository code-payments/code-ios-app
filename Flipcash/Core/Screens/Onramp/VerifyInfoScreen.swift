//
//  VerifyInfoScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-03-02.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct VerifyInfoScreen<P: PhoneVerifying, E: EmailVerifying>: View {

    @Bindable private var viewModel: OnrampVerificationViewModel<P, E>

    @Environment(\.dismiss) private var dismiss

    // MARK: - Init -

    init(viewModel: OnrampVerificationViewModel<P, E>) {
        self.viewModel = viewModel
    }

    // MARK: - Body -

    var body: some View {
        NavigationStack(path: $viewModel.verificationPath) {
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
                        viewModel.navigateToInitialVerification()
                    }
                    .buttonStyle(.filled)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton {
                        dismiss()
                    }
                }
            }
            .navigationDestination(for: OnrampVerificationPath.self) { path in
                switch path {
                case .enterPhoneNumber:
                    EnterPhoneScreen(viewModel: viewModel.phoneVerifier)
                        .interactiveDismissDisabled()
                case .confirmPhoneNumberCode:
                    ConfirmPhoneScreen(viewModel: viewModel.phoneVerifier)
                        .interactiveDismissDisabled()
                case .enterEmail:
                    EnterEmailScreen(viewModel: viewModel.emailVerifier)
                        .interactiveDismissDisabled()
                case .confirmEmailCode:
                    ConfirmEmailScreen(viewModel: viewModel.emailVerifier)
                        .interactiveDismissDisabled()
                }
            }
            .ignoresSafeArea(.keyboard)
        }
    }
}
