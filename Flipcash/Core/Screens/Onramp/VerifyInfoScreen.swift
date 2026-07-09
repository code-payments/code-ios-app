//
//  VerifyInfoScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-03-02.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// Hosts the Coinbase verification flow. The sheet's root IS the first
/// needed step — email entry normally, phone entry first when the phone is
/// unverified — with no intro page. Subsequent steps push onto
/// `verificationPath` via the verifier callbacks.
struct VerifyInfoScreen<P: PhoneVerifying, E: EmailVerifying>: View {

    @Bindable private var viewModel: OnrampVerificationViewModel<P, E>

    @State private var initialStep: OnrampVerificationPath

    @Environment(\.dismiss) private var dismiss

    // MARK: - Init -

    init(viewModel: OnrampVerificationViewModel<P, E>) {
        self.viewModel = viewModel
        _initialStep = State(initialValue: viewModel.initialStep())
    }

    // MARK: - Body -

    var body: some View {
        NavigationStack(path: $viewModel.verificationPath) {
            Group {
                switch initialStep {
                case .enterPhoneNumber, .confirmPhoneNumberCode:
                    EnterPhoneScreen(viewModel: viewModel.phoneVerifier)
                        .navigationTitle("Verify Phone Number")
                case .enterEmail, .confirmEmailCode:
                    EnterEmailScreen(viewModel: viewModel.emailVerifier)
                }
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
                        .navigationTitle("Verify Phone Number")
                case .confirmPhoneNumberCode:
                    ConfirmPhoneScreen(viewModel: viewModel.phoneVerifier)
                        .interactiveDismissDisabled()
                        .navigationTitle("Verify Phone Number")
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
        .task {
            switch initialStep {
            case .enterPhoneNumber, .confirmPhoneNumberCode:
                Analytics.track(event: Analytics.OnrampEvent.showEnterPhone)
            case .enterEmail, .confirmEmailCode:
                Analytics.track(event: Analytics.OnrampEvent.showEnterEmail)
            }
        }
    }
}
