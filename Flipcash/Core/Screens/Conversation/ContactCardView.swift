//
//  ContactCardView.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import Contacts
import ContactsUI

/// What the contact-card sheet shows: an existing address-book contact's card,
/// or an unknown counterpart offered up for adding to Contacts. Drives
/// `.sheet(item:)` directly.
enum ContactCard: Identifiable {
    /// Native card for a contact already in the address book.
    case existing(CNContact)
    /// Native "Add to Contacts" sheet (Create New / Add to Existing) seeded
    /// with what we know about a counterpart who isn't a contact yet.
    case unknown(CNContact)

    var id: String {
        switch self {
        case .existing(let contact): return "existing-\(contact.identifier)"
        case .unknown(let contact): return "unknown-\(contact.identifier)"
        }
    }
}

/// The native iOS contact card (`CNContactViewController`), hosted in a
/// navigation controller so it presents cleanly as a sheet with a Done button.
struct ContactCardView: UIViewControllerRepresentable {

    let card: ContactCard
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller: CNContactViewController
        switch card {
        case .existing(let contact):
            controller = CNContactViewController(for: contact)
        case .unknown(let contact):
            controller = CNContactViewController(forUnknownContact: contact)
            // Required for the Create New / Add to Existing actions to save.
            controller.contactStore = CNContactStore()
        }
        controller.allowsEditing = true
        controller.allowsActions = true
        // The existing card's own Edit button occupies the trailing slot, so
        // Done goes leading for both modes to stay consistent.
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .done,
            primaryAction: UIAction { [dismiss] _ in dismiss() }
        )
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}
}
