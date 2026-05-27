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
/// confirms a verified phone and authorized contacts.
///
/// Reads the contact-sync tables (`flipcash_contacts`,
/// `local_contacts_snapshot`) populated by `ContactSyncController`, joins
/// each snapshot entry against `CNContactStore` for the display name and
/// thumbnail, and renders two sections: contacts already on Flipcash and
/// contacts the user can invite. Reload triggers on appear and on
/// `CNContactStoreDidChange` so the picker tracks address-book edits.
///
/// Row tap actions are stubbed pending Phase 6 (invite sheet) and Phase 7
/// (resolve-and-send wire-up).
struct RecipientPickerScreen: View {

    let sessionContainer: SessionContainer

    @State private var contacts: ResolvedContacts = .empty
    @State private var filtered: ResolvedContacts = .empty
    @State private var isLoading: Bool = true
    @State private var searchText: String = ""

    var body: some View {
        Group {
            if isLoading {
                RecipientPickerLoadingState()
            } else if contacts.isEmpty {
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
        .task {
            await reload()
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .CNContactStoreDidChange) {
                await reload()
            }
        }
        .onChange(of: searchText) { refilter() }
        .onChange(of: contacts) { refilter() }
    }

    // MARK: - Reload -

    private func reload() async {
        contacts = await RecipientLoader.load(database: sessionContainer.database)
        isLoading = false
    }

    private func refilter() {
        filtered = contacts.filtered(by: searchText)
    }
}

// MARK: - States -

private struct RecipientPickerLoadingState: View {
    var body: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

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

// MARK: - Resolved data -

nonisolated struct ResolvedContact: Identifiable, Hashable, Sendable {
    let id: String          // CNContact.identifier
    let displayName: String
    let phoneE164: String
    let nationalPhone: String
    let imageData: Data?
}

nonisolated struct ResolvedContacts: Equatable, Sendable {
    var onFlipcash: [ResolvedContact]
    var invite: [ResolvedContact]

    static let empty = Self(onFlipcash: [], invite: [])

    var isEmpty: Bool { onFlipcash.isEmpty && invite.isEmpty }

    /// Case-insensitive substring match on `displayName` OR `nationalPhone`.
    /// Empty/whitespace-only query returns `self` unchanged.
    func filtered(by query: String) -> ResolvedContacts {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return self }
        let lowered = trimmed.lowercased()
        return ResolvedContacts(
            onFlipcash: onFlipcash.filter { $0.matches(lowered) },
            invite: invite.filter { $0.matches(lowered) },
        )
    }
}

nonisolated private extension ResolvedContact {
    func matches(_ loweredQuery: String) -> Bool {
        displayName.lowercased().contains(loweredQuery)
            || nationalPhone.lowercased().contains(loweredQuery)
    }
}

// MARK: - Loader -

/// Reads contact-sync DB tables and resolves each snapshot entry against
/// `CNContactStore`. All work runs in a detached task so the main actor
/// stays free while we hit SQLite and the Contacts TCC layer.
enum RecipientLoader {

    /// One row per unique address-book contact, with the e164 we should
    /// display chosen by ``placements(snapshot:flipcashSet:)``. The
    /// snapshot table dedupes by `e164` only, so a single contact with
    /// multiple phone-number entries (Home / Work / iPhone) yields
    /// multiple snapshot rows that share `contactId`.
    nonisolated struct ContactPlacement: Equatable, Sendable {
        let contactId: String
        let e164: String
        let isOnFlipcash: Bool
    }

    /// Group snapshot rows by `contactId` and pick a single e164 per
    /// contact. Preference order:
    /// 1. The first e164 we encounter that is in `flipcashSet` — that's
    ///    the address the user can send to right now.
    /// 2. Otherwise, the first e164 we encountered for that contact.
    ///
    /// Result order is first-seen, so callers can sort independently.
    nonisolated static func placements(
        snapshot: [Database.LocalContact],
        flipcashSet: Set<String>,
    ) -> [ContactPlacement] {
        var byContactId: [String: ContactPlacement] = [:]
        var orderedIds: [String] = []
        for entry in snapshot {
            let isMatched = flipcashSet.contains(entry.e164)
            if let existing = byContactId[entry.contactId] {
                // Promote to a matched e164 if we haven't seen one yet.
                if !existing.isOnFlipcash, isMatched {
                    byContactId[entry.contactId] = ContactPlacement(
                        contactId: entry.contactId,
                        e164: entry.e164,
                        isOnFlipcash: true,
                    )
                }
            } else {
                byContactId[entry.contactId] = ContactPlacement(
                    contactId: entry.contactId,
                    e164: entry.e164,
                    isOnFlipcash: isMatched,
                )
                orderedIds.append(entry.contactId)
            }
        }
        return orderedIds.compactMap { byContactId[$0] }
    }

    static func load(database: Database) async -> ResolvedContacts {
        await Task.detached(priority: .userInitiated) {
            let snapshot: [Database.LocalContact]
            let flipcashSet: Set<String>
            do {
                snapshot = try database.localContactsSnapshot()
                flipcashSet = Set(try database.flipcashContacts())
            } catch {
                logger.error("Failed to read contact-sync tables", metadata: [
                    "error": "\(error)",
                ])
                return ResolvedContacts.empty
            }

            let store = CNContactStore()
            // `CNContactFormatter.descriptorForRequiredKeys(for:)` returns the
            // full key set the formatter needs — including locale-specific
            // ones like `middleName`. Fetching with a smaller list crashes
            // with `CNPropertyNotFetchedException` the moment the formatter
            // reaches a property that wasn't in `keysToFetch`.
            let keys: [CNKeyDescriptor] = [
                CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
                CNContactThumbnailImageDataKey as CNKeyDescriptor,
            ]
            let region = Region.current ?? .us
            let placements = placements(snapshot: snapshot, flipcashSet: flipcashSet)

            var onFlipcash: [ResolvedContact] = []
            var invite: [ResolvedContact] = []
            let onFlipcashCount = placements.lazy.filter(\.isOnFlipcash).count
            onFlipcash.reserveCapacity(onFlipcashCount)
            invite.reserveCapacity(placements.count - onFlipcashCount)

            for placement in placements {
                guard let cnContact = try? store.unifiedContact(
                    withIdentifier: placement.contactId,
                    keysToFetch: keys,
                ) else {
                    continue
                }

                let nationalPhone = Phone(placement.e164, defaultRegion: region)?.national ?? placement.e164
                let displayName = CNContactFormatter.string(from: cnContact, style: .fullName)
                    ?? nationalPhone

                let resolved = ResolvedContact(
                    id: placement.contactId,
                    displayName: displayName,
                    phoneE164: placement.e164,
                    nationalPhone: nationalPhone,
                    imageData: cnContact.thumbnailImageData,
                )

                if placement.isOnFlipcash {
                    onFlipcash.append(resolved)
                } else {
                    invite.append(resolved)
                }
            }

            let sorter: (ResolvedContact, ResolvedContact) -> Bool = {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            onFlipcash.sort(by: sorter)
            invite.sort(by: sorter)

            return ResolvedContacts(onFlipcash: onFlipcash, invite: invite)
        }.value
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
                    id: contact.id,
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
