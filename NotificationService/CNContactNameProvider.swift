//
//  CNContactNameProvider.swift
//  NotificationService
//

import Contacts
import FlipcashCore

/// `CNContactStore`-backed display-name resolver.
///
/// Conforms `@unchecked Sendable` because `CNContactStore` is not marked
/// `Sendable` but Apple documents it as thread-safe.
final class CNContactNameProvider: ContactNameProviding, @unchecked Sendable {

    private let store = CNContactStore()

    func displayName(forContactId id: String) -> String? {
        let keys = [CNContactFormatter.descriptorForRequiredKeys(for: .fullName)]
        guard let contact = try? store.unifiedContact(withIdentifier: id, keysToFetch: keys) else {
            return nil
        }
        return CNContactFormatter.string(from: contact, style: .fullName)
    }
}
