//
//  Database+ContactSyncTests.swift
//  FlipcashTests
//

import Testing
import Foundation
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
            checksum: Data(repeating: 0xab, count: 32),
            changeHistory: Data([0x01, 0x02, 0x03]),
            lastSyncedAt: Date(timeIntervalSince1970: 1_716_000_000)
        )

        try db.setContactSyncState(state)

        #expect(try db.contactSyncState() == state)
    }

    @Test("setContactSyncState upserts on the singleton row")
    func state_upsert() throws {
        let db = Database.mock
        let first = Database.ContactSyncState(
            checksum: Data(repeating: 0x01, count: 32),
            changeHistory: nil,
            lastSyncedAt: nil
        )
        let second = Database.ContactSyncState(
            checksum: Data(repeating: 0x02, count: 32),
            changeHistory: Data([0xff]),
            lastSyncedAt: .now
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

    @Test("replaceFlipcashContacts then read returns the same set")
    func contacts_roundTrip() throws {
        let db = Database.mock
        let phones = ["+15551234567", "+447700900000", "+5215551234567"]

        try db.replaceFlipcashContacts(phones, matchedAt: .now)

        #expect(Set(try db.flipcashContacts()) == Set(phones))
    }

    @Test("replaceFlipcashContacts replaces the existing set wholesale")
    func contacts_replaceIsWholesale() throws {
        let db = Database.mock
        try db.replaceFlipcashContacts(["+15551234567", "+447700900000"], matchedAt: .now)
        try db.replaceFlipcashContacts(["+5215551234567"], matchedAt: .now)

        #expect(try db.flipcashContacts() == ["+5215551234567"])
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
}
