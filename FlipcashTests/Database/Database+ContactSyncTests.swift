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
        // Integer-second epoch round-trips losslessly through SQLite's Date
        // column; `.now` carries sub-second precision the storage truncates,
        // which made the `==` flake. Different epoch from `state_roundTrip`
        // so the upsert is still meaningful (the second value must overwrite
        // the first).
        let second = Database.ContactSyncState(
            checksum: Data(repeating: 0x02, count: 32),
            changeHistory: Data([0xff]),
            lastSyncedAt: Date(timeIntervalSince1970: 1_716_000_001)
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

    @Test("replaceFlipcashContacts with empty array drains the table")
    func contacts_replaceWithEmptyDrains() throws {
        let db = Database.mock
        try db.replaceFlipcashContacts(["+15551234567", "+447700900000"], matchedAt: .now)
        try db.replaceFlipcashContacts([], matchedAt: .now)

        #expect(try db.flipcashContacts().isEmpty)
    }

    @Test("replaceFlipcashContacts deduplicates a server-emitted duplicate")
    func contacts_dedupesDuplicateInput() throws {
        let db = Database.mock
        try db.replaceFlipcashContacts(
            ["+15551234567", "+15551234567", "+15551234567"],
            matchedAt: .now
        )

        #expect(try db.flipcashContacts() == ["+15551234567"])
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

    @Test("replaceLocalContactsSnapshot dedupes linked iOS contacts by e164, keeping first contactId")
    func snapshot_dedupesByE164KeepingFirst() throws {
        let db = Database.mock
        try db.replaceLocalContactsSnapshot([
            Database.LocalContact(e164: "+15551234567", contactId: "work-card"),
            Database.LocalContact(e164: "+15551234567", contactId: "personal-card"),
            Database.LocalContact(e164: "+447700900000", contactId: "abroad"),
        ])

        // Asserts as a set — the read query has no ORDER BY, so the
        // dedup-keep-first invariant lives in the (e164, contactId) pair,
        // not in row ordering. The "work-card" id is what proves "first wins"
        // (vs. "personal-card" if the dedup picked the last occurrence).
        #expect(Set(try db.localContactsSnapshot()) == [
            Database.LocalContact(e164: "+15551234567", contactId: "work-card"),
            Database.LocalContact(e164: "+447700900000", contactId: "abroad"),
        ])
    }
}
