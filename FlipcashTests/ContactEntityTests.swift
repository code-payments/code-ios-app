//
//  ContactEntityTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite("Contact App Entity")
struct ContactEntityTests {

    private func contact(_ name: String) -> ResolvedContact {
        ResolvedContact(
            contactId: "contact-\(name)",
            displayName: name,
            phoneE164: "+15555550\(name.count)",
            nationalPhone: "(555) 555-010\(name.count)",
            imageData: Data([0x01]),
            dmChatID: nil
        )
    }

    @Test("Maps a resolved contact onto the lean entity, dropping image and chat id")
    func mapsResolvedContact() {
        let resolved = contact("Anna")
        let entity = ContactEntity(resolved)

        #expect(entity.id == resolved.id)
        #expect(entity.displayName == "Anna")
        #expect(entity.nationalPhone == resolved.nationalPhone)
    }

    @Test("Entity id matches the resolved contact id, so perform() can re-resolve it")
    func idRoundTripsForReResolution() {
        let resolved = contact("Ben")
        let entity = ContactEntity(resolved)

        // The id is the (contactId|e164) composite the live list is keyed by.
        #expect(entity.id == "\(resolved.contactId)|\(resolved.phoneE164)")
    }

    @Test("Display representation shows the name as title and number as subtitle")
    func displayRepresentation() throws {
        let resolved = contact("Anna")
        let representation = ContactEntity(resolved).displayRepresentation

        #expect(String(localized: representation.title) == "Anna")
        let subtitle = try #require(representation.subtitle)
        #expect(String(localized: subtitle) == resolved.nationalPhone)
    }
}
