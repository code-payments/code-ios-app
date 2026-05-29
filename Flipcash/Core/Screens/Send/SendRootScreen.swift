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
    @State private var didResolveContactsStatus = false

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
            case .loading:
                // Contacts status not yet resolved, or the matched set is still
                // syncing. A neutral spinner avoids flashing the permission
                // priming screen at a user who already granted access.
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .needsContacts:
                ContactsPermissionScreen(
                    authorizer: contactsAuthorizer,
                    onAllowed: { contactSyncController.activate() },
                    onSkipped: nil
                )
            case .ready:
                RecipientPickerScreen(isLimitedAccess: contactsAuthorizer.status.isLimited)
            }
        }
        .task { await resolveContactsAccess() }
        .sheet(item: $phoneVerificationViewModel.cancellingOnDismiss()) { viewModel in
            PhoneVerificationFlowScreen(viewModel: viewModel)
        }
    }

    // MARK: - Step -

    private enum Step {
        case needsPhone
        case loading
        case needsContacts
        case ready
    }

    private var step: Step {
        guard session.profile?.isPhoneVerified ?? false else {
            return .needsPhone
        }
        guard didResolveContactsStatus else {
            return .loading
        }
        guard contactsAuthorizer.status.allowsContactAccess else {
            return .needsContacts
        }
        return contactSyncController.hasResolvedOnce ? .ready : .loading
    }

    // MARK: - Contacts access -

    /// Resolves the live contacts status before the gate runs so the priming
    /// screen never flashes for a user who already granted full or limited
    /// access, and activates the sync controller when access is in place.
    private func resolveContactsAccess() async {
        await contactsAuthorizer.refresh()
        didResolveContactsStatus = true
        if contactsAuthorizer.status.allowsContactAccess {
            contactSyncController.activate()
        }
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

