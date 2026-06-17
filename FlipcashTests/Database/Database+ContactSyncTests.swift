//
//  Database+ContactSyncTests.swift
//  FlipcashTests
//

import Testing
import Foundation
import FlipcashCore
@testable import Flipcash

@Suite("Database+ContactSync")
struct DatabaseContactSyncTests {

    // MARK: - Sync State -

    @Test("contactSyncState returns empty state when no row exists")
    func state_emptyOnFreshDatabase() throws {
        let db = Database.mock
        #expect(try db.contactSyncState() == .empty)
    }

    @Test("setContactSyncState then read returns the same state")
    func state_roundTrip() throws {
        let db = Database.mock
        let state = Database.ContactSyncState(
            checksum: Data(repeating: 0xab, count: 32)
        )

        try db.setContactSyncState(state)

        #expect(try db.contactSyncState() == state)
    }

    @Test("setContactSyncState upserts on the singleton row")
    func state_upsert() throws {
        let db = Database.mock
        let first = Database.ContactSyncState(
            checksum: Data(repeating: 0x01, count: 32)
        )
        // Different checksum so the upsert is meaningful — the second value
        // must overwrite the first on the singleton row.
        let second = Database.ContactSyncState(
            checksum: Data(repeating: 0x02, count: 32)
        )

        try db.setContactSyncState(first)
        try db.setContactSyncState(second)

        #expect(try db.contactSyncState() == second)
    }

    // MARK: - Flipcash Contacts -

    @Test("flipcashContacts is empty on a fresh database")
    func contacts_emptyOnFreshDatabase() throws {
        let db = Database.mock
        #expect(try db.flipcashContacts().isEmpty)
    }

    @Test("replaceFlipcashContacts then read returns the same set, including DM chat IDs")
    func contacts_roundTrip() throws {
        let db = Database.mock
        let contacts = [
            MatchedContact(e164: "+15551234567", dmChatID: Data(repeating: 0x01, count: 32)),
            MatchedContact(e164: "+447700900000", dmChatID: nil),
            MatchedContact(e164: "+5215551234567", dmChatID: Data(repeating: 0x02, count: 32)),
        ]

        try db.replaceFlipcashContacts(contacts, matchedAt: .now)

        #expect(Set(try db.flipcashContacts()) == Set(contacts))
    }

    @Test("replaceFlipcashContacts replaces the existing set wholesale")
    func contacts_replaceIsWholesale() throws {
        let db = Database.mock
        try db.replaceFlipcashContacts([MatchedContact(e164: "+15551234567"), MatchedContact(e164: "+447700900000")], matchedAt: .now)
        try db.replaceFlipcashContacts([MatchedContact(e164: "+5215551234567")], matchedAt: .now)

        #expect(try db.flipcashContacts() == [MatchedContact(e164: "+5215551234567")])
    }

    @Test("replaceFlipcashContacts with empty array drains the table")
    func contacts_replaceWithEmptyDrains() throws {
        let db = Database.mock
        try db.replaceFlipcashContacts([MatchedContact(e164: "+15551234567"), MatchedContact(e164: "+447700900000")], matchedAt: .now)
        try db.replaceFlipcashContacts([], matchedAt: .now)

        #expect(try db.flipcashContacts().isEmpty)
    }

    @Test("replaceFlipcashContacts deduplicates a server-emitted duplicate on e164")
    func contacts_dedupesDuplicateInput() throws {
        let db = Database.mock
        try db.replaceFlipcashContacts(
            [
                MatchedContact(e164: "+15551234567", dmChatID: Data(repeating: 0x01, count: 32)),
                MatchedContact(e164: "+15551234567", dmChatID: nil),
                MatchedContact(e164: "+15551234567", dmChatID: Data(repeating: 0x02, count: 32)),
            ],
            matchedAt: .now
        )

        // First occurrence wins, including its DM chat ID.
        #expect(try db.flipcashContacts() == [MatchedContact(e164: "+15551234567", dmChatID: Data(repeating: 0x01, count: 32))])
    }

    // MARK: - Local Snapshot -

    @Test("localContactsSnapshot is empty on a fresh database")
    func snapshot_emptyOnFreshDatabase() throws {
        let db = Database.mock
        #expect(try db.localContactsSnapshot().isEmpty)
    }

    @Test("replaceLocalContactsSnapshot then read returns the same set")
    func snapshot_roundTrip() throws {
        let db = Database.mock
        let contacts = [
            Database.LocalContact(e164: "+15551234567", contactId: "id-1"),
            Database.LocalContact(e164: "+447700900000", contactId: "id-2"),
        ]

        try db.replaceLocalContactsSnapshot(contacts)

        #expect(Set(try db.localContactsSnapshot()) == Set(contacts))
    }

    @Test("replaceLocalContactsSnapshot replaces the existing set wholesale")
    func snapshot_replaceIsWholesale() throws {
        let db = Database.mock
        try db.replaceLocalContactsSnapshot([
            Database.LocalContact(e164: "+15551234567", contactId: "id-1"),
            Database.LocalContact(e164: "+447700900000", contactId: "id-2"),
        ])
        try db.replaceLocalContactsSnapshot([
            Database.LocalContact(e164: "+5215551234567", contactId: "id-3"),
        ])

        #expect(try db.localContactsSnapshot() == [
            Database.LocalContact(e164: "+5215551234567", contactId: "id-3")
        ])
    }

    @Test("replaceLocalContactsSnapshot with empty array drains the table")
    func snapshot_replaceWithEmptyDrains() throws {
        let db = Database.mock
        try db.replaceLocalContactsSnapshot([
            Database.LocalContact(e164: "+15551234567", contactId: "id-1"),
            Database.LocalContact(e164: "+447700900000", contactId: "id-2"),
        ])
        try db.replaceLocalContactsSnapshot([])

        #expect(try db.localContactsSnapshot().isEmpty)
    }

    @Test("replaceLocalContactsSnapshot keeps every (e164, contactId) pair")
    func snapshot_keepsEveryPairAcrossContacts() throws {
        let db = Database.mock
        try db.replaceLocalContactsSnapshot([
            Database.LocalContact(e164: "+15551234567", contactId: "work-card"),
            Database.LocalContact(e164: "+15551234567", contactId: "personal-card"),
            Database.LocalContact(e164: "+447700900000", contactId: "abroad"),
        ])

        // Composite PK (e164, contactId): the same phone number under two
        // different address-book contacts produces two rows so the picker
        // can show each name with that number.
        #expect(Set(try db.localContactsSnapshot()) == [
            Database.LocalContact(e164: "+15551234567", contactId: "work-card"),
            Database.LocalContact(e164: "+15551234567", contactId: "personal-card"),
            Database.LocalContact(e164: "+447700900000", contactId: "abroad"),
        ])
    }

    @Test("replaceLocalContactsSnapshot dedupes a repeated (e164, contactId) pair")
    func snapshot_dedupesIdenticalPair() throws {
        let db = Database.mock
        try db.replaceLocalContactsSnapshot([
            Database.LocalContact(e164: "+15551234567", contactId: "alice"),
            Database.LocalContact(e164: "+15551234567", contactId: "alice"),
            Database.LocalContact(e164: "+15551234567", contactId: "alice"),
        ])

        #expect(try db.localContactsSnapshot() == [
            Database.LocalContact(e164: "+15551234567", contactId: "alice"),
        ])
    }

    // MARK: - Combined writes -

    @Test("updateContactSyncSnapshotAndState keeps every (e164, contactId) pair for a shared number")
    func combinedWrite_keepsEveryPairForSharedNumber() throws {
        let db = Database.mock

        try db.updateContactSyncSnapshotAndState(
            snapshot: [
                Database.LocalContact(e164: "+15551234567", contactId: "work-card"),
                Database.LocalContact(e164: "+15551234567", contactId: "personal-card"),
                Database.LocalContact(e164: "+447700900000", contactId: "abroad"),
            ],
            state: .init(checksum: Data(repeating: 0xab, count: 32))
        )

        // Regression: the combined write previously deduped on e164 only,
        // collapsing a phone shared across two contacts to a single row and
        // dropping the second name from the picker. It must preserve every
        // (e164, contactId) pair, matching replaceLocalContactsSnapshot.
        #expect(Set(try db.localContactsSnapshot()) == [
            Database.LocalContact(e164: "+15551234567", contactId: "work-card"),
            Database.LocalContact(e164: "+15551234567", contactId: "personal-card"),
            Database.LocalContact(e164: "+447700900000", contactId: "abroad"),
        ])
        #expect(try db.contactSyncState().checksum == Data(repeating: 0xab, count: 32))
    }

}
