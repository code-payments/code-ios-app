//
//  CNContactNameProvider.swift
//  NotificationService
//

import Contacts
import FlipcashCore

/// `CNContactStore`-backed display-name resolver.
final class CNContactNameProvider: ContactNameProviding, @unchecked Sendable {

    nonisolated(unsafe) private static let keysToFetch: [CNKeyDescriptor] = [
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
    ]

    private let store = CNContactStore()

    func displayName(forContactId id: String) -> String? {
        guard let contact = try? store.unifiedContact(
            withIdentifier: id,
            keysToFetch: Self.keysToFetch
        ) else {
            return nil
        }
        let name = "\(contact.givenName) \(contact.familyName)"
            .trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }
}
