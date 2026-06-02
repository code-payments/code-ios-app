//
//  SendRootScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// Root view for the Send sheet. Gates entry on a verified phone and
/// accessible contacts; the satisfied state renders the recipient picker.
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
                // Resolving the contacts status, or the matched set is still
                // syncing. A neutral spinner avoids flashing the permission
                // priming screen at someone who already granted access.
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
        // Resolve the contacts status only once the phone gate is satisfied.
        // Reading a Contacts API before the permission screen trips the iOS 26
        // prompt-on-`authorizationStatus` behavior and stalls the phone step.
        .task(id: session.profile?.isPhoneVerified) {
            guard session.profile?.isPhoneVerified == true else { return }
            await contactsAuthorizer.refresh()
            didResolveContactsStatus = true
            if contactsAuthorizer.status.allowsContactAccess {
                contactSyncController.activate()
            }
        }
        .sheet(item: $phoneVerificationViewModel.cancellingOnDismiss()) { viewModel in
            PhoneVerificationFlowScreen(viewModel: viewModel)
        }
        // Surface the first-scan dialog through `session.dialogItem` so
        // `DialogWindow` shows it above the Send sheet rather than competing
        // with this screen's sheet stack. The controller signals once; clear it
        // after forwarding so it never re-presents.
        .onChange(of: contactSyncController.onFlipcashMatchCount, initial: true) { _, count in
            guard let count else { return }
            session.dialogItem = .contactsOnFlipcash(count: count)
            contactSyncController.onFlipcashMatchCount = nil
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
        return contactSyncController.isDirectoryReady ? .ready : .loading
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
