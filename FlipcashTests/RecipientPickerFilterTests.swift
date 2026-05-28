//
//  RecipientPickerFilterTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash

@Suite("ResolvedContacts.filtered(by:)")
struct ResolvedContactsFilterTests {

    private let directory = ResolvedContacts(
        onFlipcash: [
            ResolvedContact(
                contactId: "1",
                displayName: "Alice Anderson",
                phoneE164: "+15551110001",
                nationalPhone: "(555) 111-0001",
                imageData: nil
            ),
            ResolvedContact(
                contactId: "2",
                displayName: "Bob Brown",
                phoneE164: "+15552220002",
                nationalPhone: "(555) 222-0002",
                imageData: nil
            ),
        ],
        invite: [
            ResolvedContact(
                contactId: "3",
                displayName: "Carla Costa",
                phoneE164: "+15553330003",
                nationalPhone: "(555) 333-0003",
                imageData: nil
            ),
        ]
    )

    @Test("Empty query returns everything unchanged")
    func emptyQuery() {
        let filtered = directory.filtered(by: "")
        #expect(filtered.onFlipcash.count == 2)
        #expect(filtered.invite.count == 1)
    }

    @Test("Whitespace-only query returns everything unchanged")
    func whitespaceQuery() {
        let filtered = directory.filtered(by: "   ")
        #expect(filtered.onFlipcash.count == 2)
        #expect(filtered.invite.count == 1)
    }

    @Test("Name match is case-insensitive substring")
    func nameMatch() {
        let filtered = directory.filtered(by: "ali")
        #expect(filtered.onFlipcash.map(\.contactId) == ["1"])
        #expect(filtered.invite.isEmpty)
    }

    @Test("Phone match uses national format")
    func phoneMatch() {
        let filtered = directory.filtered(by: "222")
        #expect(filtered.onFlipcash.map(\.contactId) == ["2"])
        #expect(filtered.invite.isEmpty)
    }

    @Test("Query that matches across sections returns both")
    func crossSectionMatch() {
        let filtered = directory.filtered(by: "555")
        #expect(filtered.onFlipcash.count == 2)
        #expect(filtered.invite.count == 1)
    }

    @Test("Non-matching query yields empty sections")
    func noMatch() {
        let filtered = directory.filtered(by: "xyz")
        #expect(filtered.isEmpty)
    }

    @Test("isEmpty reflects both sections empty")
    func isEmptyAggregates() {
        #expect(ResolvedContacts.empty.isEmpty)
        #expect(!directory.isEmpty)
    }
}

// MARK: -

@Suite("ResolvedContacts.removing(e164:)")
struct ResolvedContactsRemovingTests {

    private let alice = ResolvedContact(
        contactId: "1",
        displayName: "Alice Anderson",
        phoneE164: "+15551110001",
        nationalPhone: "(555) 111-0001",
        imageData: nil
    )
    private let bob = ResolvedContact(
        contactId: "2",
        displayName: "Bob Brown",
        phoneE164: "+15552220002",
        nationalPhone: "(555) 222-0002",
        imageData: nil
    )
    private let carla = ResolvedContact(
        contactId: "3",
        displayName: "Carla Costa",
        phoneE164: "+15553330003",
        nationalPhone: "(555) 333-0003",
        imageData: nil
    )

    @Test("Removing a phone drops every matching row from onFlipcash")
    func removesFromOnFlipcash() {
        let directory = ResolvedContacts(onFlipcash: [alice, bob], invite: [carla])
        let result = directory.removing(e164: alice.phoneE164)
        #expect(result.onFlipcash.map(\.contactId) == [bob.contactId])
        #expect(result.invite.map(\.contactId) == [carla.contactId])
    }

    @Test("Removing a phone drops every matching row from invite")
    func removesFromInvite() {
        let directory = ResolvedContacts(onFlipcash: [alice], invite: [bob, carla])
        let result = directory.removing(e164: bob.phoneE164)
        #expect(result.onFlipcash.map(\.contactId) == [alice.contactId])
        #expect(result.invite.map(\.contactId) == [carla.contactId])
    }

    @Test("Removing a phone absent from both sections is a no-op")
    func absent_noOp() {
        let directory = ResolvedContacts(onFlipcash: [alice], invite: [carla])
        let result = directory.removing(e164: "+15559999999")
        #expect(result == directory)
    }

    @Test("Same phone under multiple contactIds removes every row")
    func multipleRowsSameE164() {
        let aliceWork = ResolvedContact(
            contactId: "1-work",
            displayName: "Alice Anderson (work)",
            phoneE164: alice.phoneE164,
            nationalPhone: alice.nationalPhone,
            imageData: nil
        )
        let directory = ResolvedContacts(onFlipcash: [alice, aliceWork, bob], invite: [])
        let result = directory.removing(e164: alice.phoneE164)
        #expect(result.onFlipcash.map(\.contactId) == [bob.contactId])
    }
}
