//
//  ContactDirectory.swift
//  Flipcash
//

import Contacts
import Foundation
import FlipcashCore

nonisolated private let logger = Logger(label: "flipcash.contact-directory")

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
///
/// Called from `ContactSyncController` after each sync; the picker reads
/// the controller's cached output rather than re-loading on every appear.
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
