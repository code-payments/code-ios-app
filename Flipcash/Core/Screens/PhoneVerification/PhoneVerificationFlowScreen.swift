//
//  PhoneVerificationFlowScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// Sheet root for standalone phone verification. Used by the Send flow to
/// gate entry behind a verified phone number. Mounted via `.sheet(item:)`
/// with a `PhoneVerificationViewModel` whose callbacks are unset, so the
/// viewmodel manages its own navigation path and resumes the awaited
/// `run()` on completion.
struct PhoneVerificationFlowScreen: View {

    @Bindable private var viewModel: PhoneVerificationViewModel

    @Environment(\.dismiss) private var dismiss

    init(viewModel: PhoneVerificationViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        NavigationStack(path: $viewModel.verificationPath) {
            EnterPhoneScreen(viewModel: viewModel)
                .navigationTitle("Connect Phone Number")
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        CloseButton {
                            dismiss()
                        }
                    }
                }
                .navigationDestination(for: PhoneVerificationPath.self) { path in
                    switch path {
                    case .confirmPhoneNumberCode:
                        ConfirmPhoneScreen(viewModel: viewModel)
                            .interactiveDismissDisabled()
                    }
                }
                .ignoresSafeArea(.keyboard)
        }
    }
}
