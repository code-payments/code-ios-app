//
//  Database+ContactSync.swift
//  Flipcash
//

import Foundation
import FlipcashCore
import SQLite

nonisolated extension Database {

    // MARK: - Sync State -

    /// The contact-sync state machine's persisted cursor.
    /// `nil` fields indicate first-run state.
    struct ContactSyncState: Equatable, Sendable {
        let checksum: Data?
        let changeHistory: Data?
        let lastSyncedAt: Date?

        static let empty = ContactSyncState(checksum: nil, changeHistory: nil, lastSyncedAt: nil)
    }

    func contactSyncState() throws -> ContactSyncState {
        let table = ContactSyncStateTable()
        guard let row = try reader.pluck(table.table.filter(table.id == 1)) else {
            return .empty
        }
        return ContactSyncState(
            checksum: row[table.checksum],
            changeHistory: row[table.changeHistory],
            lastSyncedAt: row[table.lastSyncedAt]
        )
    }

    func setContactSyncState(_ state: ContactSyncState) throws {
        let table = ContactSyncStateTable()
        try writer.transaction {
            try writer.run(
                table.table.upsert(
                    table.id <- 1,
                    table.checksum <- state.checksum,
                    table.changeHistory <- state.changeHistory,
                    table.lastSyncedAt <- state.lastSyncedAt,
                    onConflictOf: table.id
                )
            )
        }
    }

    // MARK: - Flipcash Contacts -

    /// E.164 phone numbers the server has confirmed are on Flipcash.
    func flipcashContacts() throws -> [String] {
        let table = FlipcashContactTable()
        let rows = try reader.prepareRowIterator(table.table.select(table.e164))
        return try rows.map { $0[table.e164] }
    }

    /// Replace the matched-contacts set with the server's latest response.
    /// Atomic — readers observe either the old set or the new set, never a partial join.
    /// Deduplicates `e164s` defensively in case the server ever streams the same number twice.
    func replaceFlipcashContacts(_ e164s: [String], matchedAt: Date) throws {
        let table = FlipcashContactTable()
        var seen: Set<String> = []
        let deduped = e164s.filter { seen.insert($0).inserted }
        try writer.transaction {
            try writer.run(table.table.delete())
            for e164 in deduped {
                try writer.run(
                    table.table.insert(
                        table.e164 <- e164,
                        table.matchedAt <- matchedAt
                    )
                )
            }
        }
    }

    // MARK: - Local Snapshot -

    /// One row per phone in the last successfully-uploaded contact set.
    /// `contactId` is `CNContact.identifier` for resolving name/avatar at render time.
    struct LocalContact: Equatable, Hashable, Sendable {
        let e164: String
        let contactId: String
    }

    func localContactsSnapshot() throws -> [LocalContact] {
        let table = LocalContactsSnapshotTable()
        let rows = try reader.prepareRowIterator(table.table)
        return try rows.map { row in
            LocalContact(e164: row[table.e164], contactId: row[table.contactId])
        }
    }

    /// Replace the snapshot with the latest uploaded set.
    /// Composite PK `(e164, contactId)` lets the same phone show up under
    /// multiple address-book contacts (the picker shows each name with
    /// that number). Dedupe defensively on the tuple in case the source
    /// ever emits the same pair twice.
    func replaceLocalContactsSnapshot(_ contacts: [LocalContact]) throws {
        let table = LocalContactsSnapshotTable()
        var seen: Set<LocalContact> = []
        let deduped = contacts.filter { seen.insert($0).inserted }
        try writer.transaction {
            try writer.run(table.table.delete())
            for contact in deduped {
                try writer.run(
                    table.table.insert(
                        table.e164 <- contact.e164,
                        table.contactId <- contact.contactId
                    )
                )
            }
        }
    }

    // MARK: - Combined writes -

    /// Replace the snapshot AND upsert the sync state in one transaction.
    func updateContactSyncSnapshotAndState(
        snapshot contacts: [LocalContact],
        state: ContactSyncState
    ) throws {
        let snapshotTable = LocalContactsSnapshotTable()
        let stateTable    = ContactSyncStateTable()

        var seen: Set<String> = []
        let dedupedSnapshot = contacts.filter { seen.insert($0.e164).inserted }

        try writer.transaction {
            try writer.run(snapshotTable.table.delete())
            for contact in dedupedSnapshot {
                try writer.run(
                    snapshotTable.table.insert(
                        snapshotTable.e164 <- contact.e164,
                        snapshotTable.contactId <- contact.contactId
                    )
                )
            }

            try writer.run(
                stateTable.table.upsert(
                    stateTable.id <- 1,
                    stateTable.checksum <- state.checksum,
                    stateTable.changeHistory <- state.changeHistory,
                    stateTable.lastSyncedAt <- state.lastSyncedAt,
                    onConflictOf: stateTable.id
                )
            )
        }
    }
}
