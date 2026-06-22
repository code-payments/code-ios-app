//
//  ContactEntity.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import AppIntents
import FlipcashCore

/// A sendable Flipcash contact, exposed to Siri and the Shortcuts app as the
/// recipient parameter of ``SendCashIntent``. Lean by design: the live
/// `ResolvedContact` (with its image and chat id) is re-resolved by `id` at
/// `perform()` time so the entity payload stays small and never goes stale.
struct ContactEntity: AppEntity {

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Contact")
    static let defaultQuery = ContactEntityQuery()

    /// The `ResolvedContact.id` composite (`contactId|e164`).
    let id: String
    let displayName: String
    let nationalPhone: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)", subtitle: "\(nationalPhone)")
    }
}

extension ContactEntity {
    init(_ contact: ResolvedContact) {
        self.id = contact.id
        self.displayName = contact.displayName
        self.nationalPhone = contact.nationalPhone
    }
}

/// Resolves ``ContactEntity`` values from the live sendable-contact list.
/// Returns nothing when the user is logged out or can't send, so the parameter
/// offers no suggestions and the shortcut stays inert.
struct ContactEntityQuery: EntityQuery {

    func entities(for identifiers: [String]) async throws -> [ContactEntity] {
        let wanted = Set(identifiers)
        return await AppIntentContext.sendableContacts()
            .filter { wanted.contains($0.id) }
            .map(ContactEntity.init)
    }

    func suggestedEntities() async throws -> [ContactEntity] {
        await AppIntentContext.sendableContacts().map(ContactEntity.init)
    }
}

extension ContactEntityQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [ContactEntity] {
        let lowered = string.lowercased()
        return await AppIntentContext.sendableContacts()
            .filter {
                $0.displayName.lowercased().contains(lowered)
                    || $0.nationalPhone.contains(string)
            }
            .map(ContactEntity.init)
    }
}
