//
//  SendRootScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// Root view for the Send sheet. Gates entry on a verified phone and
/// authorized contacts; the satisfied state renders the recipient picker.
struct SendRootScreen: View {

    @Environment(Session.self) private var session
    @Environment(ContactSyncController.self) private var contactSyncController
    @Environment(AppRouter.self) private var router

    @State private var phoneVerificationViewModel: PhoneVerificationViewModel?
    @State private var contactsAuthorizer = ContactsAuthorizer()

    private let container: Container

    // MARK: - Init -

    init(container: Container) {
        self.container = container
    }

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            switch step {
            case .needsPhone:
                ConnectPhoneEmptyState(onConnect: startPhoneVerification)
            case .needsContacts:
                ContactsPermissionScreen(
                    authorizer: contactsAuthorizer,
                    onAllowed: { contactSyncController.activate() },
                    onSkipped: nil
                )
            case .loadingContacts:
                // Already authorized; controller is resolving the directory
                // for the first time this session. Keep the priming screen
                // visible with a spinner on the primary button so the user
                // sees clear in-progress feedback instead of a flash to a
                // half-populated picker.
                ContactsPermissionScreen(
                    authorizer: contactsAuthorizer,
                    onAllowed: { contactSyncController.activate() },
                    onSkipped: nil,
                    isAllowing: true
                )
            case .ready:
                RecipientPickerScreen()
            }
        }
        .sheet(item: $phoneVerificationViewModel.cancellingOnDismiss()) { viewModel in
            PhoneVerificationFlowScreen(viewModel: viewModel)
        }
    }

    // MARK: - Step -

    private enum Step {
        case needsPhone
        case needsContacts
        case loadingContacts
        case ready
    }

    private var step: Step {
        guard session.profile?.isPhoneVerified ?? false else {
            return .needsPhone
        }
        guard contactsAuthorizer.status == .authorized else {
            return .needsContacts
        }
        return contactSyncController.hasResolvedOnce ? .ready : .loadingContacts
    }

    // MARK: - Phone verification handoff -

    private func startPhoneVerification() {
        let viewModel = PhoneVerificationViewModel(
            session: session,
            flipClient: container.flipClient,
            enterPhoneEvent: Analytics.SendEvent.showEnterPhone,
            confirmPhoneEvent: Analytics.SendEvent.showConfirmPhone
        )
        phoneVerificationViewModel = viewModel

        Task { [weak viewModel] in
            try? await viewModel?.run()
            phoneVerificationViewModel = nil
        }
    }
}

