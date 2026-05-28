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
    /// `contactId` from `CNContact.identifier`. The same person may appear
    /// in several `ResolvedContact`s, one per phone number, and the same
    /// number may show up under several contactIds — so `contactId` alone
    /// is NOT unique. Use ``id`` for `ForEach`. `contactId` is for things
    /// scoped to the address-book record (image cache, send wire-up).
    let contactId: String
    let displayName: String
    let phoneE164: String
    let nationalPhone: String
    let imageData: Data?

    /// Composite identity for `ForEach`. A picker row corresponds to one
    /// (contactId, e164) pair; the same address-book contact with three
    /// phones is three rows with three distinct `id`s.
    var id: String { "\(contactId)|\(phoneE164)" }
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

    /// Returns a copy with every row matching `e164` dropped from both sections.
    func removing(e164: String) -> ResolvedContacts {
        ResolvedContacts(
            onFlipcash: onFlipcash.filter { $0.phoneE164 != e164 },
            invite: invite.filter { $0.phoneE164 != e164 },
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

    /// One placement per snapshot row. The snapshot now uses a composite
    /// `(e164, contactId)` PK, so each pair survives — multiple phones on
    /// one contact, or one phone shared across multiple contacts, all
    /// come through here.
    nonisolated struct ContactPlacement: Equatable, Sendable {
        let contactId: String
        let e164: String
        let isOnFlipcash: Bool
    }

    /// Direct map of every snapshot row to a placement, annotated with
    /// whether the e164 is on Flipcash. No grouping or filtering.
    nonisolated static func placements(
        snapshot: [Database.LocalContact],
        flipcashSet: Set<String>,
    ) -> [ContactPlacement] {
        snapshot.map { entry in
            ContactPlacement(
                contactId: entry.contactId,
                e164: entry.e164,
                isOnFlipcash: flipcashSet.contains(entry.e164),
            )
        }
    }

    /// Collapse contacts that look identical to the user — same display
    /// name and same nationally-formatted phone number — to a single
    /// row. Different underlying e164s that format to the same national
    /// string (extension trailers, formatting variants) count as the
    /// same row. On a collision, prefer the variant whose e164 is on
    /// Flipcash so the resulting row is the actionable one.
    ///
    /// Result preserves first-seen order, mirroring ``placements``.
    nonisolated static func deduplicatedForDisplay(
        _ contacts: [ResolvedContact],
        flipcashSet: Set<String>,
    ) -> [ResolvedContact] {
        // Struct key (not a separator-joined string) — display names and
        // phone formats can legitimately contain any character, and a
        // joined-string key would collide when the separator appears in
        // the data itself.
        struct Key: Hashable {
            let displayName: String
            let nationalPhone: String
        }
        var byKey: [Key: ResolvedContact] = [:]
        var orderedKeys: [Key] = []
        for contact in contacts {
            let key = Key(displayName: contact.displayName, nationalPhone: contact.nationalPhone)
            if let existing = byKey[key] {
                let existingMatched = flipcashSet.contains(existing.phoneE164)
                let newMatched      = flipcashSet.contains(contact.phoneE164)
                if !existingMatched, newMatched {
                    byKey[key] = contact
                }
            } else {
                byKey[key] = contact
                orderedKeys.append(key)
            }
        }
        return orderedKeys.compactMap { byKey[$0] }
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

            // Resolve every placement first; cache `unifiedContact` lookups
            // so the same contactId across rows doesn't hit CN repeatedly.
            var resolvedByPlacement: [ResolvedContact] = []
            resolvedByPlacement.reserveCapacity(placements.count)
            var cnCache: [String: CNContact] = [:]

            for placement in placements {
                let cnContact: CNContact
                if let cached = cnCache[placement.contactId] {
                    cnContact = cached
                } else if let fetched = try? store.unifiedContact(
                    withIdentifier: placement.contactId,
                    keysToFetch: keys,
                ) {
                    cnCache[placement.contactId] = fetched
                    cnContact = fetched
                } else {
                    continue
                }

                let nationalPhone = Phone(placement.e164, defaultRegion: region)?.national ?? placement.e164
                let displayName   = CNContactFormatter.string(from: cnContact, style: .fullName)
                    ?? nationalPhone

                resolvedByPlacement.append(ResolvedContact(
                    contactId: placement.contactId,
                    displayName: displayName,
                    phoneE164: placement.e164,
                    nationalPhone: nationalPhone,
                    imageData: cnContact.thumbnailImageData,
                ))
            }

            // Collapse `(displayName, nationalPhone)` collisions — Ted's
            // invariant: don't ever show the same name + number twice.
            let unique = deduplicatedForDisplay(resolvedByPlacement, flipcashSet: flipcashSet)

            var onFlipcash: [ResolvedContact] = []
            var invite: [ResolvedContact] = []
            for contact in unique {
                if flipcashSet.contains(contact.phoneE164) {
                    onFlipcash.append(contact)
                } else {
                    invite.append(contact)
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
