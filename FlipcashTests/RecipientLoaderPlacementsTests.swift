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

    @Test("Single phone — single placement")
    func singlePhoneSinglePlacement() {
        let snapshot = [
            LocalContact(e164: "+14085551111", contactId: "A"),
        ]
        let placements = RecipientLoader.placements(snapshot: snapshot, flipcashSet: [])

        #expect(placements == [
            Placement(contactId: "A", e164: "+14085551111", isOnFlipcash: false),
        ])
    }

    @Test("Multiple phones on the same contact yield ONE placement")
    func dedupesByContactId() {
        let snapshot = [
            LocalContact(e164: "+14085551111;ext=100", contactId: "A"),
            LocalContact(e164: "+14085551111;ext=200", contactId: "A"),
            LocalContact(e164: "+14085551111;ext=300", contactId: "A"),
        ]
        let placements = RecipientLoader.placements(snapshot: snapshot, flipcashSet: [])

        #expect(placements.count == 1)
        #expect(placements[0].contactId == "A")
        #expect(placements[0].e164 == "+14085551111;ext=100")  // first-seen wins
    }

    @Test("Matched phone wins over earlier unmatched phone on the same contact")
    func matchedPhonePromotes() {
        let snapshot = [
            LocalContact(e164: "+14085551111", contactId: "A"),     // home, not on Flipcash
            LocalContact(e164: "+14085552222", contactId: "A"),     // cell, on Flipcash
        ]
        let placements = RecipientLoader.placements(
            snapshot: snapshot,
            flipcashSet: ["+14085552222"],
        )

        #expect(placements == [
            Placement(contactId: "A", e164: "+14085552222", isOnFlipcash: true),
        ])
    }

    @Test("First matched phone is kept; later matched phones do not overwrite")
    func firstMatchedWins() {
        let snapshot = [
            LocalContact(e164: "+14085551111", contactId: "A"),     // on Flipcash
            LocalContact(e164: "+14085552222", contactId: "A"),     // also on Flipcash
        ]
        let placements = RecipientLoader.placements(
            snapshot: snapshot,
            flipcashSet: ["+14085551111", "+14085552222"],
        )

        #expect(placements == [
            Placement(contactId: "A", e164: "+14085551111", isOnFlipcash: true),
        ])
    }

    @Test("Distinct contacts produce distinct placements in first-seen order")
    func ordersByFirstSeen() {
        let snapshot = [
            LocalContact(e164: "+14085551111", contactId: "C"),
            LocalContact(e164: "+14085552222", contactId: "A"),
            LocalContact(e164: "+14085553333", contactId: "B"),
        ]
        let placements = RecipientLoader.placements(snapshot: snapshot, flipcashSet: [])

        #expect(placements.map(\.contactId) == ["C", "A", "B"])
    }

    @Test("Empty snapshot yields no placements")
    func emptySnapshot() {
        let placements = RecipientLoader.placements(snapshot: [], flipcashSet: ["+14085551111"])
        #expect(placements.isEmpty)
    }

    @Test("isOnFlipcash reflects flipcashSet membership for the chosen e164")
    func isOnFlipcashReflectsChosenE164() {
        let snapshot = [
            LocalContact(e164: "+14085551111", contactId: "A"),
            LocalContact(e164: "+14085552222", contactId: "B"),
            LocalContact(e164: "+14085553333", contactId: "C"),
        ]
        let placements = RecipientLoader.placements(
            snapshot: snapshot,
            flipcashSet: ["+14085552222"],
        )

        #expect(placements.first { $0.contactId == "A" }?.isOnFlipcash == false)
        #expect(placements.first { $0.contactId == "B" }?.isOnFlipcash == true)
        #expect(placements.first { $0.contactId == "C" }?.isOnFlipcash == false)
    }
}
