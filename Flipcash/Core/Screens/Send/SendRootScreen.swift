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

    @Environment(Container.self) private var container
    @Environment(Session.self) private var session
    @Environment(ContactSyncController.self) private var contactSyncController
    @Environment(ConversationController.self) private var conversationController
    @Environment(AppRouter.self) private var router

    @State private var phoneVerificationViewModel: PhoneVerificationViewModel?
    @State private var contactsAuthorizer = ContactsAuthorizer()
    @State private var didResolveContactsStatus = false
    @State private var searchText = ""

    // MARK: - Body -

    var body: some View {
        @Bindable var router = router
        return Group {
            switch step {
            case .ready(let access):
                // The ready state gets its own stack so the search field is
                // scoped to it — the phone/contacts gating states below use a
                // separate stack with no `.searchable`.
                NavigationStack(path: $router[.send]) {
                    Background(color: .backgroundMain) {
                        RecipientPickerScreen(
                            contactAccess: access,
                            searchText: searchText
                        )
                    }
                    .appRouterDestinations()
                    .navigationTitle("Send")
                    .toolbarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            CloseButton(action: router.dismissSheet)
                        }
                    }
                    .searchable(
                        text: $searchText,
                        prompt: "Search Contacts"
                    )
                }
            default:
                // Phone / contacts gating — a separate stack with no search bar.
                NavigationStack {
                    Background(color: .backgroundMain) {
                        switch step {
                        case .needsPhone:
                            ConnectPhoneEmptyState(onConnect: startPhoneVerification)
                        case .loading:
                            // Resolving the contacts status, or the matched set is
                            // still syncing. A neutral spinner avoids flashing the
                            // permission priming screen at someone who already
                            // granted access.
                            ProgressView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        case .needsContacts, .deniedNoRecents:
                            // Both the undetermined pitch and the denied warning
                            // are rendered by `ContactsPermissionScreen`, which
                            // picks the event from the authorizer's status.
                            ContactsPermissionScreen(
                                authorizer: contactsAuthorizer,
                                onAllowed: { contactSyncController.activate() }
                            )
                        case .ready:
                            EmptyView()
                        }
                    }
                    .navigationTitle("Send")
                    .toolbarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            CloseButton(action: router.dismissSheet)
                        }
                    }
                }
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
        case deniedNoRecents
        case ready(RecipientContactAccess)
    }

    private var step: Step {
        guard session.profile?.isPhoneVerified ?? false else {
            return .needsPhone
        }
        guard didResolveContactsStatus else {
            return .loading
        }
        // `.notDetermined` isn't picker-reachable — route it to the priming screen.
        guard let access = RecipientContactAccess(contactsAuthorizer.status) else {
            return .needsContacts
        }
        switch access {
        case .denied:
            // Contacts are unavailable. With recent chats, drop into the picker
            // so it shows them alongside the CTA card; with none, show the
            // full-screen pitch instead — but wait out the first-login feed load
            // so an in-flight fetch doesn't flash the empty state before its
            // conversations arrive.
            guard conversationController.conversations.isEmpty else {
                return .ready(access)
            }
            return conversationController.isLoadingFeed ? .loading : .deniedNoRecents
        case .full, .limited:
            return contactSyncController.isDirectoryReady ? .ready(access) : .loading
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
