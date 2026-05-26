//
//  ContactsAuthorizer.swift
//  FlipcashUI
//

import SwiftUI
import Contacts

@Observable
public class ContactsAuthorizer {

    public var status: CNAuthorizationStatus = .notDetermined

    // MARK: - Init -

    public init() {
        updateStatus()
    }

    // MARK: - Authorize -

    /// Prompts the user once when the status is `.notDetermined`, then returns
    /// the resolved authorization status. For `.denied` / `.restricted` /
    /// `.limited` callers should route the user to Settings — iOS suppresses
    /// repeat prompts.
    public func authorize() async -> CNAuthorizationStatus {
        let current = CNContactStore.authorizationStatus(for: .contacts)
        guard current == .notDetermined else {
            return current
        }

        let store = CNContactStore()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.requestAccess(for: .contacts) { _, _ in
                continuation.resume()
            }
        }

        updateStatus()
        return status
    }

    private func updateStatus() {
        status = CNContactStore.authorizationStatus(for: .contacts)
    }
}
