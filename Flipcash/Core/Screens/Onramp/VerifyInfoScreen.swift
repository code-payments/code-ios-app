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
                case .intro:
                    OnrampVerificationIntroScreen(onNext: { viewModel.proceedFromIntro() })
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
                case .intro:
                    // Only ever the stack root, never pushed; handled for exhaustiveness.
                    OnrampVerificationIntroScreen(onNext: { viewModel.proceedFromIntro() })
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
            case .intro:
                break // The intro tracks showEnterPhone when the user proceeds.
            case .enterPhoneNumber, .confirmPhoneNumberCode:
                Analytics.track(event: Analytics.OnrampEvent.showEnterPhone)
            case .enterEmail, .confirmEmailCode:
                Analytics.track(event: Analytics.OnrampEvent.showEnterEmail)
            }
        }
    }
}

/// Renders one verification step when the flow is pushed onto the app's
/// navigation stack (v2) rather than hosted in `VerifyInfoScreen`'s own sheet
/// stack. Mirrors the per-step switch above. The active view model comes from
/// the coordinator's inline slot; the root step cancels the flow when it's
/// popped — the user backed out of verification — while later steps back
/// within the flow. Registered on every stack by `appRouterDestinations()`.
struct OnrampVerificationPushedStep: View {

    let path: OnrampVerificationPath

    @Environment(VerificationCoordinator.self) private var coordinator

    var body: some View {
        if let viewModel = coordinator.currentInlineViewModel {
            step(for: path, viewModel: viewModel)
                .toolbarTitleDisplayMode(.inline)
                .onDisappear {
                    // Popping the root step means the user abandoned
                    // verification; cancel to release the awaiting gate. A
                    // no-op once the flow has finished (continuation cleared).
                    if path == viewModel.rootPushedStep {
                        viewModel.cancel()
                    }
                }
        }
    }

    @ViewBuilder
    private func step(for path: OnrampVerificationPath, viewModel: OnrampVerification) -> some View {
        switch path {
        case .intro:
            OnrampVerificationIntroScreen(onNext: { viewModel.proceedFromIntro() })
        case .enterPhoneNumber:
            EnterPhoneScreen(viewModel: viewModel.phoneVerifier)
                .navigationTitle("Verify Phone Number")
        case .confirmPhoneNumberCode:
            ConfirmPhoneScreen(viewModel: viewModel.phoneVerifier)
                .navigationTitle("Verify Phone Number")
        case .enterEmail:
            EnterEmailScreen(viewModel: viewModel.emailVerifier)
        case .confirmEmailCode:
            ConfirmEmailScreen(viewModel: viewModel.emailVerifier)
        }
    }
}
