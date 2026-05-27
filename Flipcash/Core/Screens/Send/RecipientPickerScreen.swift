//
//  RecipientPickerScreen.swift
//  Flipcash
//

import Contacts
import SwiftUI
import FlipcashCore
import FlipcashUI

nonisolated private let logger = Logger(label: "flipcash.recipient-picker")

/// The Send section's primary view. Shown after the `SendRootScreen` gate
/// confirms a verified phone, authorized contacts, AND that
/// `ContactSyncController` has resolved the directory at least once.
///
/// Reads the controller's `resolvedContacts` cache directly — no internal
/// loading state. Refreshes happen invisibly on the controller side; the
/// picker observes the updated value and re-renders without ever flipping
/// to a spinner.
///
/// Row tap actions are stubbed pending Phase 6 (invite sheet) and Phase 7
/// (resolve-and-send wire-up).
struct RecipientPickerScreen: View {

    @Environment(ContactSyncController.self) private var contactSyncController

    @State private var filtered: ResolvedContacts = .empty
    @State private var searchText: String = ""

    var body: some View {
        let contacts = contactSyncController.resolvedContacts
        return Group {
            if contacts.isEmpty {
                RecipientPickerEmptyState()
            } else {
                VStack(spacing: 0) {
                    InlineSearchField(text: $searchText)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                    RecipientPickerList(
                        filtered: filtered,
                        searchText: searchText,
                        onFlipcashTap: { _ in
                            // Phase 7 wires this to `session.send` once
                            // `PaymentDestinationService.resolve(phone:)` is in.
                            logger.info("Tapped On Flipcash row (send wire-up pending)")
                        },
                        onInviteTap: { _ in
                            // Phase 6 wires this to `MessageComposerSheet`.
                            logger.info("Tapped Invite row (composer sheet pending)")
                        }
                    )
                }
            }
        }
        .onAppear { refilter() }
        .onChange(of: searchText) { refilter() }
        .onChange(of: contacts) { refilter() }
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
    let onFlipcashTap: (ResolvedContact) -> Void
    let onInviteTap: (ResolvedContact) -> Void

    var body: some View {
        List {
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
            if !searchText.isEmpty && filtered.isEmpty {
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
