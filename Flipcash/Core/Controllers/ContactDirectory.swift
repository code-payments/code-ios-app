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
    /// The server-issued DM ChatId for this contact; nil until contact sync
    /// has stored one. A chat that doesn't exist yet is initiated by sending
    /// the contact cash.
    let dmChatID: Data?
    /// When this contact joined Flipcash, from the matched-contact set. Sorts a
    /// chat-less contact into the recipient list by recency. `nil` for a
    /// not-on-Flipcash contact and when the server omits it.
    let joinDate: Date?

    init(contactId: String, displayName: String, phoneE164: String, nationalPhone: String, imageData: Data?, dmChatID: Data? = nil, joinDate: Date? = nil) {
        self.contactId = contactId
        self.displayName = displayName
        self.phoneE164 = phoneE164
        self.nationalPhone = nationalPhone
        self.imageData = imageData
        self.dmChatID = dmChatID
        self.joinDate = joinDate
    }

    /// Composite identity for `ForEach`. A picker row corresponds to one
    /// (contactId, e164) pair; the same address-book contact with three
    /// phones is three rows with three distinct `id`s.
    var id: String { "\(contactId)|\(phoneE164)" }
}

extension ResolvedContact {
    /// Builds a send target for a DM counterpart who isn't in the address book,
    /// from the phone number the server shared on their chat member, so Send Cash
    /// works before the person is a synced contact. `nil` when no number is on
    /// file. The phone resolves the recipient and `dmChatID` carries the chat
    /// payment metadata; the display fields aren't read by the send flow.
    nonisolated init?(counterpart member: ConversationMember, dmChatID: Data?) {
        guard let phoneE164 = member.phoneE164, !phoneE164.isEmpty else { return nil }
        let national = member.formattedPhoneNumber ?? phoneE164
        self.init(
            contactId: phoneE164,
            displayName: national,
            phoneE164: phoneE164,
            nationalPhone: national,
            imageData: nil,
            dmChatID: dmChatID
        )
    }
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

    /// One row per displayed phone number. A payment to a number reaches the
    /// same recipient regardless of which contact it came from, so contacts
    /// that share a nationally-formatted number — including extension/format
    /// variants of one e164 — collapse to a single row. On a collision the
    /// most useful label wins, in order: a real name beats a bare-number
    /// fallback; then an on-Flipcash (sendable) e164 beats one that isn't;
    /// then, between two different named contacts, the last-seen one wins;
    /// otherwise the first-seen row stays.
    nonisolated static func deduplicatedForDisplay(
        _ contacts: [ResolvedContact],
        flipcashSet: Set<String>,
    ) -> [ResolvedContact] {
        var byNumber: [String: ResolvedContact] = [:]
        var order: [String] = []
        for contact in contacts {
            let key = contact.nationalPhone
            guard let existing = byNumber[key] else {
                byNumber[key] = contact
                order.append(key)
                continue
            }
            if prefers(contact, over: existing, flipcashSet: flipcashSet) {
                byNumber[key] = contact
            }
        }
        return order.compactMap { byNumber[$0] }
    }

    /// Whether `candidate` is a better row than `existing` for the same number.
    private nonisolated static func prefers(
        _ candidate: ResolvedContact,
        over existing: ResolvedContact,
        flipcashSet: Set<String>,
    ) -> Bool {
        // A resolved contact with no name falls back to its own number as the
        // display name; a real name is more useful than that bare number.
        let candidateNamed = candidate.displayName != candidate.nationalPhone
        let existingNamed   = existing.displayName != existing.nationalPhone
        if candidateNamed != existingNamed { return candidateNamed }

        let candidateMatched = flipcashSet.contains(candidate.phoneE164)
        let existingMatched   = flipcashSet.contains(existing.phoneE164)
        if candidateMatched != existingMatched { return candidateMatched }

        // Two different named contacts on one number: the last-seen wins.
        // Variants of the same contact keep the first/base e164.
        return candidateNamed && candidate.contactId != existing.contactId
    }

    /// Drops the user's own contact: you can't send to yourself, so your own
    /// number never belongs in the recipient list even when it's saved in your
    /// address book. A `nil`/empty self phone leaves the list untouched.
    nonisolated static func excludingSelf(
        _ contacts: [ResolvedContact],
        selfPhone: String?,
    ) -> [ResolvedContact] {
        guard let selfPhone, !selfPhone.isEmpty else { return contacts }
        return contacts.filter { $0.phoneE164 != selfPhone }
    }

    static func load(database: Database) async -> ResolvedContacts {
        await Task.detached(priority: .userInitiated) {
            let snapshot: [Database.LocalContact]
            let matched: [MatchedContact]
            do {
                snapshot = try database.localContactsSnapshot()
                matched = try database.flipcashContacts()
            } catch {
                logger.error("Failed to read contact-sync tables", metadata: [
                    "error": "\(error)",
                ])
                return ResolvedContacts.empty
            }
            // Best-effort: a missing profile just leaves the list unfiltered.
            let selfPhone = try? database.getProfile()?.phone?.e164
            let flipcashSet = Set(matched.map(\.e164))
            let dmChatIDByPhone = Dictionary(
                matched.compactMap { contact in contact.dmChatID.map { (contact.e164, $0) } },
                uniquingKeysWith: { first, _ in first }
            )
            let joinDateByPhone = Dictionary(
                matched.compactMap { contact in contact.joinDate.map { (contact.e164, $0) } },
                uniquingKeysWith: { first, _ in first }
            )

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

            // Resolve every snapshot row first; cache `unifiedContact` lookups
            // so the same contactId across rows doesn't hit CN repeatedly.
            var resolvedByPlacement: [ResolvedContact] = []
            resolvedByPlacement.reserveCapacity(snapshot.count)
            var cnCache: [String: CNContact] = [:]
            // The same e164 recurs across rows (one contact, many rows;
            // one number, many contacts) — parse it through PhoneNumberKit once.
            var nationalCache: [String: String] = [:]

            for entry in snapshot {
                let cnContact: CNContact
                if let cached = cnCache[entry.contactId] {
                    cnContact = cached
                } else if let fetched = try? store.unifiedContact(
                    withIdentifier: entry.contactId,
                    keysToFetch: keys,
                ) {
                    cnCache[entry.contactId] = fetched
                    cnContact = fetched
                } else {
                    continue
                }

                let nationalPhone: String
                if let cached = nationalCache[entry.e164] {
                    nationalPhone = cached
                } else {
                    nationalPhone = Phone(entry.e164, defaultRegion: region)?.national ?? entry.e164
                    nationalCache[entry.e164] = nationalPhone
                }
                let displayName   = CNContactFormatter.string(from: cnContact, style: .fullName)
                    ?? nationalPhone

                resolvedByPlacement.append(ResolvedContact(
                    contactId: entry.contactId,
                    displayName: displayName,
                    phoneE164: entry.e164,
                    nationalPhone: nationalPhone,
                    imageData: cnContact.thumbnailImageData,
                    dmChatID: dmChatIDByPhone[entry.e164],
                    joinDate: joinDateByPhone[entry.e164],
                ))
            }

            // Collapse `(displayName, nationalPhone)` collisions so the same
            // display name + national number is never shown twice.
            let unique = deduplicatedForDisplay(
                excludingSelf(resolvedByPlacement, selfPhone: selfPhone),
                flipcashSet: flipcashSet,
            )

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
