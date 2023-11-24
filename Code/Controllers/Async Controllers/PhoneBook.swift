//
//  PhoneBook.swift
//  Code
//
//  Created by Dima Bart on 2021-03-17.
//

import Foundation
import CodeServices
import Contacts

@CronActor
class PhoneBook {
    
    nonisolated var authorizationStatus: CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    private(set) var contacts: [Contact] = []
    
    private let store = CNContactStore()
    
    // MARK: - Init -
    
    nonisolated init() {}
    
    // MARK: - Authorization -
    
    func requestAccessIfNeeded() async throws {
        if authorizationStatus != .authorized {
            do {
                try await store.requestAccess(for: .contacts)
            } catch {
                trace(.failure, components: "Failed to grant access to Address Book: \(error)")
            }
        }
    }
    
    // MARK: - Contacts -
    
    func fetchContacts() async throws {
        return try await withCheckedThrowingContinuation { c in
            do {
                let keys: [CNKeyDescriptor] = [
                    CNContactGivenNameKey as NSString,
                    CNContactFamilyNameKey as NSString,
                    CNContactOrganizationNameKey as NSString,
                    CNContactPhoneNumbersKey as NSString,
                ]
                
                // Fetch all contacts from all containers
                let addressBookContacts = try store.containers(matching: nil).flatMap { container in
                    try store.unifiedContacts(matching: container.contactsPredicate, keysToFetch: keys)
                }
                
                // For each contact:
                //  1. Parse the phone number and discard if invalid
                //  2. Duplicate the `Contact` for each phone number in the contact
                
                let contacts = addressBookContacts.flatMap { contact -> [Contact] in
                    let uniquePhoneNumbers = Set(contact.phoneNumbers.compactMap { Phone($0.value.stringValue) })
                    return uniquePhoneNumbers.map { phone -> Contact in
                        Contact(
                            id: contact.identifier,
                            firstName: contact.givenName,
                            lastName: contact.familyName,
                            company: contact.organizationName,
                            phoneNumber: phone
                        )
                    }
                    
                // Will remove duplicates, unique ID constructed with '\(id)\(phoneNumber)'
                }.elementsKeyed(by: \.uniqueIdentifier).values
                
                self.contacts = Array(contacts)
                c.resume(returning: ())
                
            } catch {
                trace(.failure, components: "Failed to fetch contacts: \(error)")
                c.resume(throwing: error)
            }
        }
    }
}

private extension CNContainer {
    var contactsPredicate: NSPredicate {
        CNContact.predicateForContactsInContainer(withIdentifier: identifier)
    }
}

// MARK: - Mock -

extension PhoneBook {
    static let mock = PhoneBook()
}
