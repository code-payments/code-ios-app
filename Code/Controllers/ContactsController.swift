//
//  ContactsController.swift
//  Code
//
//  Created by Dima Bart on 2021-03-17.
//

import Foundation
import CodeServices
import Contacts

@MainActor
class ContactsController: ObservableObject {
    
    @Published private(set) var status: CNAuthorizationStatus = .notDetermined
    
    @Published private(set) var isFetchingContacts = false
    
    @Published private(set) var contacts: [Contact] = []
    
    private let client: Client
    private let user: User
    private let owner: KeyPair
    
    private let phoneBook: PhoneBook
    private let uploadController: PhoneUploadController
    
    // MARK: - Init -
    
    init(client: Client, user: User, owner: KeyPair) {
        self.client = client
        self.user = user
        self.owner = owner
        
        self.phoneBook = PhoneBook()
        self.uploadController = PhoneUploadController(client: client, user: user, owner: owner)
                
        updateAuthorizationStatus()
        if status == .authorized {
            Task {
                try await fetchContactMetaData()
            }
        }
    }

    // MARK: - Authorization -
    
    private func updateAuthorizationStatus() {
        status = phoneBook.authorizationStatus
    }
    
    func requestAccessIfNeeded() async throws {
        try await phoneBook.requestAccessIfNeeded()
        updateAuthorizationStatus()
        try await fetchContactMetaData()
    }
    
    // MARK: - Contacts -
    
    func fetchContactMetadata() {
        Task {
            try await fetchContactMetaData()
        }
    }
    
    private func set(contacts: [Contact]) {
        self.contacts = contacts.sortedByAppState()
    }
    
    private func fetchContactMetaData() async throws {
        isFetchingContacts = true
        
        // Step 1: Fetch contacts from local address book
        var localContacts = await phoneBook.contacts
        if localContacts.isEmpty {
            try await phoneBook.fetchContacts()
            localContacts = await phoneBook.contacts
        }

        // Step 2: Upload all contacts to obtain
        // their status on the Code platform.
        let phones = localContacts.map { $0.phoneNumber }

        // Upload contact phone numbers only if necessary
        if await uploadController.requiresUpload(phones: phones) {
            let errors = await uploadController.batchUpload(phones: phones)
            if errors == 0 {
                trace(.success, components: "Contact upload finished.")
            } else {
                trace(.failure, components: "Contact upload finished with \(errors) errors.")
            }
        }
        
        // Step 3: Fetch the status of any identified Code contacts
        let allContacts = try await self.fetchMetadata(for: localContacts)
        
        set(contacts: allContacts)

        isFetchingContacts = false
    }
    
    private func fetchMetadata(for contacts: [Contact]) async throws -> [Contact] {
        let phoneDescriptions = try await client.fetchAppContacts(containerID: user.containerID, owner: owner)
        trace(.success, components: "Fetched \(phoneDescriptions.count) phone descriptions.")
        return updating(contacts: contacts, with: phoneDescriptions)
    }
    
    private func updating(contacts: [Contact], with descriptions: [PhoneDescription]) -> [Contact] {
        let knownPhones = descriptions.elementsKeyed(by: \.phone)
        return contacts.map {
            var updatedContact = $0
            if let description = knownPhones[$0.phoneNumber] {
                updatedContact.state = description.status.state
            } else {
                updatedContact.state = .unknown
            }
            return updatedContact
        }
    }
}

// MARK: - State -

private extension PhoneDescription.RegistraionStatus {
    var state: Contact.AppState {
        switch self {
        case .registered:
            return .registered
        case .invited:
            return .invited
        case .uploaded, .revoked:
            return .unknown
        }
    }
}

// MARK: - Mock -

extension ContactsController {
    static let mock = ContactsController(
        client: .mock,
        user: .mock,
        owner: .mock
    )
}
