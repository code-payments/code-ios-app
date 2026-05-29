//
//  RecipientPickerScreen.swift
//  Flipcash
//

import Contacts
import ContactsUI
import MessageUI
import SwiftUI
import FlipcashCore
import FlipcashUI

nonisolated private let logger = Logger(label: "flipcash.recipient-picker")

/// Send section's primary view. Renders `contactSyncController.resolvedContacts`.
struct RecipientPickerScreen: View {

    /// `true` when contacts are shared under iOS 18 limited access. Surfaces
    /// the `ContactAccessButton` affordance so the user can add more people to
    /// the shared set without granting full access.
    let isLimitedAccess: Bool

    @Environment(ContactSyncController.self) private var contactSyncController
    @Environment(AppRouter.self) private var router

    @State private var filtered: ResolvedContacts = .empty
    @State private var searchText: String = ""
    @State private var inviteTarget: ResolvedContact?

    var body: some View {
        let contacts = contactSyncController.resolvedContacts
        return Group {
            if contacts.isEmpty && !isLimitedAccess {
                RecipientPickerEmptyState()
            } else {
                VStack(spacing: 0) {
                    InlineSearchField(text: $searchText)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                    RecipientPickerList(
                        filtered: filtered,
                        searchText: searchText,
                        isLimitedAccess: isLimitedAccess,
                        onAddApproved: {
                            // Clear the query so the add affordance can't flip
                            // to its "No matches" state once the only result is
                            // added; the new contact lands in the list after
                            // the re-sync.
                            searchText = ""
                            contactSyncController.sync()
                        },
                        onFlipcashTap: selectRecipient,
                        onInviteTap: presentInvite,
                    )
                }
            }
        }
        .onAppear { refilter() }
        .onChange(of: searchText) { refilter() }
        .onChange(of: contacts) { refilter() }
        .sheet(item: $inviteTarget) { contact in
            MessageComposerSheet(
                recipient: contact.phoneE164,
                body: MessageComposerSheet.placeholderBody,
                onFinish: { result in
                    logger.info("Invite composer finished", metadata: [
                        "outcome": "\(outcomeName(result))",
                    ])
                    inviteTarget = nil
                },
            )
        }
    }

    // MARK: - Tap -

    private func selectRecipient(_ contact: ResolvedContact) {
        Analytics.track(event: Analytics.SendEvent.tapRecipient)
        router.push(.sendAmount(contact: contact))
    }

    private func presentInvite(for contact: ResolvedContact) {
        if MessageComposerSheet.isAvailable {
            inviteTarget = contact
        } else {
            // iMessage isn't configured on this device (iPad without SIM, etc.).
            // Fall back to the system share sheet with the download URL only.
            logger.info("Presenting share fallback (iMessage unavailable)")
            ShareSheet.present(url: URL.downloadApp)
        }
    }

    private func outcomeName(_ result: MessageComposeResult) -> String {
        switch result {
        case .sent:       return "sent"
        case .cancelled:  return "cancelled"
        case .failed:     return "failed"
        @unknown default: return "unknown"
        }
    }

    private func refilter() {
        filtered = contactSyncController.resolvedContacts.filtered(by: searchText)
    }
}

// MARK: - Empty state -

private struct RecipientPickerEmptyState: View {
    var body: some View {
        ContentUnavailableView(
            "No Contacts Found",
            systemImage: "person.crop.circle.badge.questionmark",
            description: Text("None of the people in your address book have a phone number we can match.")
        )
    }
}

// MARK: - Limited access -

/// iOS 18 limited-access affordance: surfaces contacts matching `queryString`
/// that aren't in the shared set yet; tapping one shares it without a
/// full-access prompt, and the approval callback re-syncs so it appears here.
///
/// Sized to mirror `RecipientRow` — 44pt avatar, 12pt gap, phone caption — so
/// the system control reads as part of the list. Its remaining system styling
/// is intentional: it signals the distinct "grant access" action.
@available(iOS 18, *)
private struct AddLimitedContactsButton: View {

    let queryString: String
    let onApproved: () -> Void

    var body: some View {
        ContactAccessButton(queryString: queryString) { _ in
            onApproved()
        }
        .backgroundStyle(Color.background)
        .contactAccessButtonCaption(.phone)
        .contactAccessButtonStyle(
            .init(imageTrailingEdgePadding: 12, imageWidth: 44, imageColor: nil)
        )
    }
}

// MARK: - Search field -

private struct InlineSearchField: View {

    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.textSecondary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .foregroundStyle(Color.textMain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.backgroundRow)
        .clipShape(Capsule())
        .padding(.horizontal, 20)
    }
}

// MARK: - List -

private struct RecipientPickerList: View {

    let filtered: ResolvedContacts
    let searchText: String
    let isLimitedAccess: Bool
    let onAddApproved: () -> Void
    let onFlipcashTap: (ResolvedContact) -> Void
    let onInviteTap: (ResolvedContact) -> Void

    var body: some View {
        List {
            if isLimitedAccess, !searchText.isEmpty {
                if #available(iOS 18, *) {
                    Section {
                        AddLimitedContactsButton(queryString: searchText, onApproved: onAddApproved)
                            .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(.rowSeparator)
                    } header: {
                        RecipientSectionHeader(title: "Add from Contacts")
                    }
                }
            }
            if !filtered.onFlipcash.isEmpty {
                Section {
                    ForEach(filtered.onFlipcash) { contact in
                        RecipientRow(
                            contact: contact,
                            trailing: .chevron,
                            onTap: { onFlipcashTap(contact) }
                        )
                    }
                } header: {
                    RecipientSectionHeader(title: "On Flipcash")
                }
            }
            if !filtered.invite.isEmpty {
                Section {
                    ForEach(filtered.invite) { contact in
                        RecipientRow(
                            contact: contact,
                            trailing: .invite { onInviteTap(contact) },
                            onTap: { onInviteTap(contact) }
                        )
                    }
                } header: {
                    RecipientSectionHeader(title: "Not on Flipcash Yet")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .overlay {
            if !searchText.isEmpty && filtered.isEmpty && !isLimitedAccess {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }
}

// MARK: - Row -

private enum RecipientRowTrailing {
    case chevron
    case invite(() -> Void)
}

private struct RecipientRow: View {

    let contact: ResolvedContact
    let trailing: RecipientRowTrailing
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ContactAvatarView(
                    id: contact.contactId,
                    displayName: contact.displayName,
                    imageData: contact.imageData,
                    size: 44
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.displayName)
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                        .lineLimit(1)
                    Text(contact.nationalPhone)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                RecipientRowTrailingAccessory(trailing: trailing)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20))
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(.rowSeparator)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(contact.displayName), \(contact.nationalPhone)"))
        .accessibilityAddTraits(.isButton)
        .accessibilityActions {
            if case .invite(let action) = trailing {
                Button("Invite", action: action)
            }
        }
    }
}

private struct RecipientRowTrailingAccessory: View {

    let trailing: RecipientRowTrailing

    var body: some View {
        switch trailing {
        case .chevron:
            Image(systemName: "chevron.right")
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)
        case .invite(let action):
            Button(action: action) {
                Text("Invite")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textMain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        RoundedRectangle(cornerRadius: Metrics.buttonRadius)
                            .fill(Color.backgroundRow)
                    }
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Section header -

/// Opaque section header. List's `.plain` style sticky-pins headers as the
/// user scrolls; without a background, the row content underneath shows
/// through the floating header. `Color.backgroundMain` matches the sheet
/// backdrop so the header reads as a solid bar.
private struct RecipientSectionHeader: View {

    let title: String

    var body: some View {
        Text(title)
            .textCase(.none)
            .font(.appTextSmall)
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.backgroundMain)
            .listRowInsets(EdgeInsets())
    }
}
