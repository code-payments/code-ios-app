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
    /// A `nil` checksum indicates first-run state.
    public struct ContactSyncState: Equatable, Sendable {
        public let checksum: Data?

        public init(checksum: Data?) {
            self.checksum = checksum
        }

        public static let empty = ContactSyncState(checksum: nil)
    }

    public func contactSyncState() throws -> ContactSyncState {
        let table = ContactSyncStateTable()
        guard let row = try reader.pluck(table.table.filter(table.id == 1)) else {
            return .empty
        }
        return ContactSyncState(checksum: row[table.checksum])
    }

    public func setContactSyncState(_ state: ContactSyncState) throws {
        let table = ContactSyncStateTable()
        try writer.transaction {
            try writer.run(
                table.table.upsert(
                    table.id <- 1,
                    table.checksum <- state.checksum,
                    onConflictOf: table.id
                )
            )
        }
    }

    // MARK: - Flipcash Contacts -

    /// Contacts the server has confirmed are on Flipcash, with their DM chat IDs.
    public func flipcashContacts() throws -> [MatchedContact] {
        let table = FlipcashContactTable()
        let rows = try reader.prepareRowIterator(table.table.select(table.e164, table.dmChatId, table.joinTs))
        return try rows.map { MatchedContact(e164: $0[table.e164], dmChatID: $0[table.dmChatId], joinDate: $0[table.joinTs]) }
    }

    /// Replace the matched-contacts set with the server's latest response and
    /// return the deduped count persisted.
    /// Atomic — readers observe either the old set or the new set, never a partial join.
    /// Deduplicates on `e164` defensively in case the server ever streams the same number twice.
    @discardableResult
    public func replaceFlipcashContacts(_ contacts: [MatchedContact], matchedAt: Date) throws -> Int {
        let table = FlipcashContactTable()
        var seen: Set<String> = []
        let deduped = contacts.filter { seen.insert($0.e164).inserted }
        try writer.transaction {
            try writer.run(table.table.delete())
            for contact in deduped {
                try writer.run(
                    table.table.insert(
                        table.e164 <- contact.e164,
                        table.dmChatId <- contact.dmChatID,
                        table.joinTs <- contact.joinDate,
                        table.matchedAt <- matchedAt
                    )
                )
            }
        }
        return deduped.count
    }

    // MARK: - Local Snapshot -

    /// One row per phone in the last successfully-uploaded contact set.
    /// `contactId` is `CNContact.identifier` for resolving name/avatar at render time.
    public struct LocalContact: Equatable, Hashable, Sendable {
        public let e164: String
        public let contactId: String

        public init(e164: String, contactId: String) {
            self.e164 = e164
            self.contactId = contactId
        }
    }

    public func localContactsSnapshot() throws -> [LocalContact] {
        let table = LocalContactsSnapshotTable()
        let rows = try reader.prepareRowIterator(table.table)
        return try rows.map { row in
            LocalContact(e164: row[table.e164], contactId: row[table.contactId])
        }
    }

    /// Replace the snapshot with the latest uploaded set.
    public func replaceLocalContactsSnapshot(_ contacts: [LocalContact]) throws {
        try writer.transaction {
            try rewriteLocalContactsSnapshot(contacts)
        }
    }

    /// Dedupes on the full `(e164, contactId)` tuple — the composite PK that lets the
    /// same phone appear under multiple address-book contacts (the picker shows each
    /// name with that number) — then rewrites the snapshot table. Must be called
    /// inside a `writer.transaction`.
    private func rewriteLocalContactsSnapshot(_ contacts: [LocalContact]) throws {
        let table = LocalContactsSnapshotTable()
        var seen: Set<LocalContact> = []
        let deduped = contacts.filter { seen.insert($0).inserted }
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

    // MARK: - Combined writes -

    /// Replace the snapshot AND upsert the sync state in one transaction.
    public func updateContactSyncSnapshotAndState(
        snapshot contacts: [LocalContact],
        state: ContactSyncState
    ) throws {
        let stateTable = ContactSyncStateTable()
        try writer.transaction {
            try rewriteLocalContactsSnapshot(contacts)
            try writer.run(
                stateTable.table.upsert(
                    stateTable.id <- 1,
                    stateTable.checksum <- state.checksum,
                    onConflictOf: stateTable.id
                )
            )
        }
    }
}
