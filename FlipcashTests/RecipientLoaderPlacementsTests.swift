//
//  RecipientLoaderPlacementsTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash

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

    @Test("Same number under multiple names collapses to one — the last-seen named wins")
    func sameNumberMultipleNames() {
        let contacts = [
            makeContact(contactId: "A", name: "Alice", e164: "+14085551234", national: "(408) 555-1234"),
            makeContact(contactId: "B", name: "Bob",   e164: "+14085551234", national: "(408) 555-1234"),
        ]
        let unique = RecipientLoader.deduplicatedForDisplay(contacts, flipcashSet: [])
        #expect(unique.count == 1)
        #expect(unique[0].displayName == "Bob")
    }

    @Test("A named contact wins over a no-name duplicate on the same number")
    func namedWinsOverNoName() {
        let national = "(408) 555-1234"
        let contacts = [
            // No-name contact: its label falls back to the bare number.
            makeContact(contactId: "A", name: national, e164: "+14085551234", national: national),
            makeContact(contactId: "B", name: "Ted",    e164: "+14085551234", national: national),
        ]
        let unique = RecipientLoader.deduplicatedForDisplay(contacts, flipcashSet: [])
        #expect(unique.count == 1)
        #expect(unique[0].displayName == "Ted")
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

    /// Regression: a joined-string key like `"\(displayName)|\(nationalPhone)"`
    /// would collide for these two contacts on the boundary character.
    /// The struct-key implementation keeps them distinct.
    @Test("Display strings containing a literal pipe do NOT collide")
    func pipeCharacterDoesNotCollide() {
        let contacts = [
            makeContact(contactId: "A", name: "Alice|Smith", e164: "+14085551111", national: "(408) 555-1111"),
            makeContact(contactId: "B", name: "Alice",       e164: "+14085552222", national: "Smith|(408) 555-1111"),
        ]
        let unique = RecipientLoader.deduplicatedForDisplay(contacts, flipcashSet: [])
        #expect(unique.count == 2)
        #expect(Set(unique.map(\.displayName)) == ["Alice|Smith", "Alice"])
    }
}

@Suite("RecipientLoader.excludingSelf(_:selfPhone:)")
struct RecipientLoaderExcludingSelfTests {

    private func makeContact(e164: String) -> ResolvedContact {
        ResolvedContact(
            contactId: e164,
            displayName: "Name \(e164)",
            phoneE164: e164,
            nationalPhone: e164,
            imageData: nil,
        )
    }

    @Test("Drops the contact matching the user's own number")
    func dropsSelf() {
        let contacts = [makeContact(e164: "+14085551111"), makeContact(e164: "+14085552222")]
        let result = RecipientLoader.excludingSelf(contacts, selfPhone: "+14085551111")
        #expect(result.map(\.phoneE164) == ["+14085552222"])
    }

    @Test("Drops every row sharing the user's number")
    func dropsAllSelfRows() {
        let contacts = [
            makeContact(e164: "+14085551111"),
            makeContact(e164: "+14085551111"),
            makeContact(e164: "+14085552222"),
        ]
        let result = RecipientLoader.excludingSelf(contacts, selfPhone: "+14085551111")
        #expect(result.map(\.phoneE164) == ["+14085552222"])
    }

    @Test("Leaves the list untouched when self phone is nil")
    func nilSelfPhoneKeepsAll() {
        let contacts = [makeContact(e164: "+14085551111"), makeContact(e164: "+14085552222")]
        let result = RecipientLoader.excludingSelf(contacts, selfPhone: nil)
        #expect(result.count == 2)
    }

    @Test("Leaves the list untouched when self phone is empty")
    func emptySelfPhoneKeepsAll() {
        let contacts = [makeContact(e164: "+14085551111")]
        let result = RecipientLoader.excludingSelf(contacts, selfPhone: "")
        #expect(result.count == 1)
    }
}
