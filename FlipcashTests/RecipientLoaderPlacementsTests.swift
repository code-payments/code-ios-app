//
//  RecipientLoaderPlacementsTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash

@Suite("RecipientLoader.placements(snapshot:flipcashSet:)")
struct RecipientLoaderPlacementsTests {

    private typealias Placement = RecipientLoader.ContactPlacement
    private typealias LocalContact = Database.LocalContact

    @Test("One placement per snapshot row, preserving order")
    func directMap() {
        let snapshot = [
            LocalContact(e164: "+14085551111", contactId: "A"),
            LocalContact(e164: "+14085552222", contactId: "B"),
        ]
        let placements = RecipientLoader.placements(snapshot: snapshot, flipcashSet: [])

        #expect(placements == [
            Placement(contactId: "A", e164: "+14085551111", isOnFlipcash: false),
            Placement(contactId: "B", e164: "+14085552222", isOnFlipcash: false),
        ])
    }

    @Test("Multiple phones on one contact each get a placement")
    func multiplePhonesPerContact() {
        let snapshot = [
            LocalContact(e164: "+14085551111", contactId: "A"),
            LocalContact(e164: "+14085552222", contactId: "A"),
            LocalContact(e164: "+14085553333", contactId: "A"),
        ]
        let placements = RecipientLoader.placements(snapshot: snapshot, flipcashSet: [])

        #expect(placements.count == 3)
        #expect(placements.allSatisfy { $0.contactId == "A" })
        #expect(placements.map(\.e164) == ["+14085551111", "+14085552222", "+14085553333"])
    }

    @Test("One phone shared across contacts each get a placement")
    func sharedPhoneAcrossContacts() {
        let snapshot = [
            LocalContact(e164: "+14085551234", contactId: "A"),
            LocalContact(e164: "+14085551234", contactId: "B"),
        ]
        let placements = RecipientLoader.placements(snapshot: snapshot, flipcashSet: [])

        #expect(placements == [
            Placement(contactId: "A", e164: "+14085551234", isOnFlipcash: false),
            Placement(contactId: "B", e164: "+14085551234", isOnFlipcash: false),
        ])
    }

    @Test("isOnFlipcash reflects flipcashSet membership for that exact e164")
    func isOnFlipcashPerE164() {
        let snapshot = [
            LocalContact(e164: "+14085551111", contactId: "A"),   // matched
            LocalContact(e164: "+14085552222", contactId: "A"),   // not
        ]
        let placements = RecipientLoader.placements(
            snapshot: snapshot,
            flipcashSet: ["+14085551111"],
        )

        #expect(placements[0].isOnFlipcash == true)
        #expect(placements[1].isOnFlipcash == false)
    }

    @Test("Empty snapshot yields no placements")
    func emptySnapshot() {
        let placements = RecipientLoader.placements(snapshot: [], flipcashSet: ["+14085551111"])
        #expect(placements.isEmpty)
    }
}

@Suite("RecipientLoader.deduplicatedForDisplay(_:flipcashSet:)")
struct RecipientLoaderDeduplicatedForDisplayTests {

    private func makeContact(
        contactId: String,
        name: String,
        e164: String,
        national: String,
    ) -> ResolvedContact {
        ResolvedContact(
            contactId: contactId,
            displayName: name,
            phoneE164: e164,
            nationalPhone: national,
            imageData: nil,
        )
    }

    @Test("Distinct (name, nationalPhone) tuples all survive")
    func distinctTuples() {
        let contacts = [
            makeContact(contactId: "A", name: "Alice", e164: "+14085551111", national: "(408) 555-1111"),
            makeContact(contactId: "B", name: "Bob",   e164: "+14085552222", national: "(408) 555-2222"),
        ]
        let unique = RecipientLoader.deduplicatedForDisplay(contacts, flipcashSet: [])
        #expect(unique.count == 2)
    }

    @Test("Same name with multiple different numbers shows once per number")
    func sameNameMultipleNumbers() {
        let contacts = [
            makeContact(contactId: "A", name: "Alice", e164: "+14085551111", national: "(408) 555-1111"),
            makeContact(contactId: "A", name: "Alice", e164: "+14085552222", national: "(408) 555-2222"),
        ]
        let unique = RecipientLoader.deduplicatedForDisplay(contacts, flipcashSet: [])
        #expect(unique.count == 2)
        #expect(unique.map(\.nationalPhone) == ["(408) 555-1111", "(408) 555-2222"])
    }

    @Test("Same number under multiple names shows once per name")
    func sameNumberMultipleNames() {
        let contacts = [
            makeContact(contactId: "A", name: "Alice", e164: "+14085551234", national: "(408) 555-1234"),
            makeContact(contactId: "B", name: "Bob",   e164: "+14085551234", national: "(408) 555-1234"),
        ]
        let unique = RecipientLoader.deduplicatedForDisplay(contacts, flipcashSet: [])
        #expect(unique.count == 2)
        #expect(Set(unique.map(\.displayName)) == ["Alice", "Bob"])
    }

    @Test("Same (name, nationalPhone) collapses to ONE row")
    func sameNameAndNumber() {
        let contacts = [
            makeContact(contactId: "A", name: "Daniel", e164: "+14085553514",          national: "(408) 555-3514"),
            makeContact(contactId: "A", name: "Daniel", e164: "+14085553514;ext=100",  national: "(408) 555-3514"),
            makeContact(contactId: "A", name: "Daniel", e164: "+14085553514;ext=200",  national: "(408) 555-3514"),
        ]
        let unique = RecipientLoader.deduplicatedForDisplay(contacts, flipcashSet: [])
        #expect(unique.count == 1)
    }

    @Test("Matched e164 wins over an earlier unmatched collision")
    func matchedWinsOverEarlierUnmatched() {
        let contacts = [
            makeContact(contactId: "A", name: "Daniel", e164: "+14085553514;ext=100",  national: "(408) 555-3514"),
            makeContact(contactId: "A", name: "Daniel", e164: "+14085553514",          national: "(408) 555-3514"),
        ]
        let unique = RecipientLoader.deduplicatedForDisplay(
            contacts,
            flipcashSet: ["+14085553514"],
        )
        #expect(unique.count == 1)
        #expect(unique[0].phoneE164 == "+14085553514")
    }

    @Test("First matched e164 stays when a later matched arrives")
    func firstMatchedStays() {
        let contacts = [
            makeContact(contactId: "A", name: "Daniel", e164: "+14085553514",          national: "(408) 555-3514"),
            makeContact(contactId: "A", name: "Daniel", e164: "+14085553514;ext=100",  national: "(408) 555-3514"),
        ]
        let unique = RecipientLoader.deduplicatedForDisplay(
            contacts,
            flipcashSet: ["+14085553514", "+14085553514;ext=100"],
        )
        #expect(unique.count == 1)
        #expect(unique[0].phoneE164 == "+14085553514")
    }

    @Test("Result preserves first-seen order")
    func preservesOrder() {
        let contacts = [
            makeContact(contactId: "C", name: "Carla", e164: "+1...3", national: "n3"),
            makeContact(contactId: "A", name: "Alice", e164: "+1...1", national: "n1"),
            makeContact(contactId: "B", name: "Bob",   e164: "+1...2", national: "n2"),
        ]
        let unique = RecipientLoader.deduplicatedForDisplay(contacts, flipcashSet: [])
        #expect(unique.map(\.displayName) == ["Carla", "Alice", "Bob"])
    }

    @Test("Empty input yields empty output")
    func emptyInput() {
        #expect(RecipientLoader.deduplicatedForDisplay([], flipcashSet: ["+1..."]).isEmpty)
    }
}
