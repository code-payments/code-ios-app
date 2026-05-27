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
        // The dev-backend mock phone (`+10000000000`) used in UI tests
        // does not link to a real user, so `profile.phone` stays nil
        // even after the verification screen completes. Bypass the gate
        // under `--ui-testing` so the smoke test can reach the picker.
        let phoneVerified = session.profile?.isPhoneVerified ?? false
        guard phoneVerified || Container.isRunningUITests else {
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
            owner: session.ownerKeyPair,
            flipClient: container.flipClient,
            enterPhoneEvent: Analytics.SendEvent.showEnterPhone,
            confirmPhoneEvent: Analytics.SendEvent.showConfirmPhone,
            isAlreadyVerified: { [weak session] in session?.profile?.isPhoneVerified ?? false },
            onShouldRefreshProfile: { [weak session] in try? await session?.updateProfile() },
        )
        phoneVerificationViewModel = viewModel

        Task { [weak viewModel] in
            try? await viewModel?.run()
            phoneVerificationViewModel = nil
        }
    }
}

