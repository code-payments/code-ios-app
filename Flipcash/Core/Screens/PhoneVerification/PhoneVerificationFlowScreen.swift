//
//  PhoneVerificationFlowScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// Sheet root for standalone phone verification. Used by the Send flow to
/// gate entry behind a verified phone number. Mounted via `.sheet(item:)`
/// with any `PhoneVerifying` conformer whose callbacks are unset, so the
/// viewmodel manages its own navigation path and resumes the awaited
/// `run()` on completion.
struct PhoneVerificationFlowScreen<VM: PhoneVerifying>: View {

    @Bindable private var viewModel: VM

    @Environment(\.dismiss) private var dismiss

    init(viewModel: VM) {
        self.viewModel = viewModel
    }

    var body: some View {
        NavigationStack(path: $viewModel.verificationPath) {
            EnterPhoneScreen(viewModel: viewModel)
                .interactiveDismissDisabled()
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
                            .navigationTitle("Connect Phone Number")
                    }
                }
                .ignoresSafeArea(.keyboard)
        }
    }
}
