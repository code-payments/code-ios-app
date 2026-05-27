//
//  SendRootScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// Root view for the Send sheet. Gates entry to the recipient picker on two
/// preconditions, in order:
///   1. The user's phone is verified.
///   2. Contacts authorization is `.authorized`.
///
/// The recipient picker itself ships in Phase 5; for now the satisfied state
/// renders a placeholder.
struct SendRootScreen: View {

    @Environment(Session.self) private var session
    @Environment(ContactSyncController.self) private var contactSyncController
    @Environment(AppRouter.self) private var router

    @State private var phoneVerificationViewModel: PhoneVerificationViewModel?
    @State private var contactsAuthorizer = ContactsAuthorizer()

    private let container: Container
    private let sessionContainer: SessionContainer

    // MARK: - Init -

    init(container: Container, sessionContainer: SessionContainer) {
        self.container        = container
        self.sessionContainer = sessionContainer
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
            case .ready:
                RecipientPickerPlaceholder()
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
        case ready
    }

    private var step: Step {
        guard session.profile?.isPhoneVerified ?? false else {
            return .needsPhone
        }
        return contactsAuthorizer.status == .authorized ? .ready : .needsContacts
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
            do {
                try await viewModel?.run()
            } catch {
                // `run()` throws `CancellationError` on swipe-dismiss or
                // viewmodel teardown; no further handling needed.
            }
            phoneVerificationViewModel = nil
        }
    }
}

// MARK: - Picker placeholder (Phase 5 fills this in) -

private struct RecipientPickerPlaceholder: View {
    var body: some View {
        // TODO(Phase 5): replace with `RecipientPickerScreen`.
        VStack(spacing: 12) {
            ProgressView()
            Text("Recipient picker arrives in Phase 5")
                .font(.appTextMedium)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
