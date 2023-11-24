//
//  Client+Contacts.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension Client {
    
    public func uploadContacts(containerID: ID, phoneNumbers: [Phone], owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            contactsService.uploadContacts(containerID: containerID, phoneNumbers: phoneNumbers, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func fetchAppContacts(containerID: ID, owner: KeyPair) async throws -> [PhoneDescription] {
        try await withCheckedThrowingContinuation { c in
            contactsService.fetchAppContacts(containerID: containerID, owner: owner) { c.resume(with: $0) }
        }
    }
}
